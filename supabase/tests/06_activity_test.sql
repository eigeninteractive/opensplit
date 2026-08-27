-- The activity log, and the dormancy jobs that eventually clear a group away.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ravi@example.com', '{"display_name":"Ravi"}', now(), now()),
  ('22222222-2222-4222-8222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'priya@example.com', '{"display_name":"Priya"}', now(), now());

insert into groups (id, name, default_currency, created_by)
values ('33333333-3333-4333-8333-333333333333', 'Flat 4B', 'INR',
        '11111111-1111-4111-8111-111111111111');

insert into members (id, group_id, profile_id, display_name) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333',
   '22222222-2222-4222-8222-222222222222', 'Priya');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
set constraints all deferred;

-- ---------------------------------------------------------------------------
-- Recording what happened
--
-- The device that made the change describes it. There used to be a SECURITY
-- DEFINER trigger on `entries` here instead, and these tests asserted that
-- saving an expense wrote its own feed line — but a trigger only fires for a
-- write that reached the server, so an app whose whole premise is that it works
-- offline had an activity feed that stayed empty until it did not.
--
-- What the server still guarantees is what is worth testing, and it is now all
-- policy rather than procedure: you may append in your own name, for an entry
-- in your own group, and nothing anywhere lets you take it back.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888',
      '33333333-3333-4333-8333-333333333333', 'INR', 40000,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":40000}]'::jsonb,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":20000},
        {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":20000}]'::jsonb,
      'Dinner')$$,
  'an expense can be recorded');

select is(
  (select count(*)::int from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  0,
  'and writes no history by itself: the client authors the feed line, so a '
  'trigger doing it too would make every event arrive twice');

select lives_ok(
  $$insert into entry_events (id, entry_id, group_id, actor_id, kind)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            '88888888-8888-4888-8888-888888888888',
            '33333333-3333-4333-8333-333333333333',
            '44444444-4444-4444-8444-444444444444', 'created')$$,
  'the member who recorded it may append the line saying so');

select is(
  (select created_at is not null from entry_events
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  true,
  'stamped by the server, not by whoever sent it: the activity cursor '
  'advances on this column, so a device with a fast clock could otherwise '
  'push it into the future and make every other device skip what came after');

select throws_ok(
  $$insert into entry_events (entry_id, group_id, actor_id, kind)
    values ('88888888-8888-4888-8888-888888888888',
            '33333333-3333-4333-8333-333333333333',
            '55555555-5555-4555-8555-555555555555', 'edited')$$,
  '42501', null,
  'but not one in somebody else''s name: Ravi cannot record that Priya did it');

-- Priya's own group, which Ravi has nothing to do with.
reset role;
reset "request.jwt.claims";
insert into groups (id, name, default_currency, created_by)
values ('66666666-6666-4666-8666-666666666666', 'Elsewhere', 'INR',
        '22222222-2222-4222-8222-222222222222');
insert into members (id, group_id, profile_id, display_name)
values ('77777777-7777-4777-8777-777777777777',
        '66666666-6666-4666-8666-666666666666',
        '22222222-2222-4222-8222-222222222222', 'Priya');
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select throws_ok(
  $$insert into entry_events (entry_id, group_id, actor_id, kind)
    values ('88888888-8888-4888-8888-888888888888',
            '66666666-6666-4666-8666-666666666666',
            '44444444-4444-4444-8444-444444444444', 'edited')$$,
  '42501', null,
  'nor file one against a group he is not in, which would put a line about '
  'his expense in front of people with no access to it');

-- ---------------------------------------------------------------------------
-- Nobody can rewrite their own history
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update entry_events set kind = 'edited'
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '42501', null,
  'an audit trail somebody can revise is not one');

select throws_ok(
  $$delete from entry_events$$,
  '42501', null,
  'nor erase one');

set constraints all immediate;

-- ---------------------------------------------------------------------------
-- Dormancy
-- ---------------------------------------------------------------------------
reset role;
reset "request.jwt.claims";

update groups set created_at = now() - interval '2 years'
 where id = '33333333-3333-4333-8333-333333333333';
update entries set created_at = now() - interval '2 years';

-- Asserted on this group rather than on the return count. Both functions are
-- global by nature, and a database that other tests have run against holds
-- their leftovers too — a count would be asserting on those.
select lives_ok(
  $$select archive_dormant_groups()$$,
  'the reaper runs');

select is(
  (select archived_at is not null from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  true,
  'a silent group is archived');

-- Priya still owes Ravi ₹200, so this group is not finished with.
select lives_ok(
  $$select purge_settled_dormant_groups()$$,
  'the purge runs');

select is(
  (select count(*)::int from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  1,
  'an unsettled group is never purged, however old: a dormant group is not a '
  'finished one, and the likeliest reason it went quiet with money '
  'outstanding is the worst reason to erase the record');

-- Settle it, and it becomes collectable.
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
set constraints all deferred;
select upsert_entry(
  '99999999-9999-4999-8999-999999999999',
  '33333333-3333-4333-8333-333333333333', 'INR', 20000,
  '[{"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":20000}]'::jsonb,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":20000}]'::jsonb,
  'Settling up', 'settlement');
set constraints all immediate;
reset role;
reset "request.jwt.claims";

update entries set created_at = now() - interval '2 years';
update groups set archived_at = now() - interval '1 year';

select lives_ok(
  $$select purge_settled_dormant_groups()$$,
  'and runs again once it is settled');

select is(
  (select count(*)::int from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  0,
  'a settled group, archived and years silent, is collected');

select * from finish();
rollback;
