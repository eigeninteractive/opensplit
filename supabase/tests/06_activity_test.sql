-- The activity log, and the dormancy jobs that eventually clear a group away.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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
  (select kind::text from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  'created',
  'creating one writes a created event');

select is(
  (select changes from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  null,
  'with no diff: "everything changed" is not a diff, and the entry itself '
  'already records what it started as');

-- The correction: ₹400 was really ₹300.
select lives_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888',
      '33333333-3333-4333-8333-333333333333', 'INR', 30000,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":30000}]'::jsonb,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":15000},
        {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":15000}]'::jsonb,
      'Dinner')$$,
  'and edited afterwards');

select is(
  (select changes from entry_events where kind = 'edited'),
  '{"amount_minor": {"to": 30000, "from": 40000}}'::jsonb,
  'the edit records what changed, from and to');

select is(
  (select actor_id from entry_events where kind = 'edited'),
  '44444444-4444-4444-8444-444444444444'::uuid,
  'attributed to the member who did it, not the account');

-- Saving something unchanged.
select lives_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888',
      '33333333-3333-4333-8333-333333333333', 'INR', 30000,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":30000}]'::jsonb,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":15000},
        {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":15000}]'::jsonb,
      'Dinner')$$,
  'saving it again unchanged is allowed');

select is(
  (select count(*)::int from entry_events where kind = 'edited'),
  1,
  'but is not an edit: a retried sync must not fill the feed with '
  '"Ravi edited nothing"');

select is(
  (select count(*)::int from entry_events
    where created_at = (select created_at from entry_events
                         where kind = 'created')),
  1,
  'events are stamped with the wall clock, not transaction time, so two in '
  'one transaction do not tie and sort by a random uuid');

-- ---------------------------------------------------------------------------
-- Nobody can write their own history
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into entry_events (entry_id, group_id, actor_id, kind)
    values ('88888888-8888-4888-8888-888888888888',
            '33333333-3333-4333-8333-333333333333',
            '44444444-4444-4444-8444-444444444444', 'edited')$$,
  '42501', null,
  'a member cannot fabricate an event');

select throws_ok(
  $$update entry_events set kind = 'created' where kind = 'edited'$$,
  '42501', null,
  'nor rewrite one: an audit trail somebody can revise is not one');

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

-- Priya still owes Ravi ₹150, so this group is not finished with.
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
  '33333333-3333-4333-8333-333333333333', 'INR', 15000,
  '[{"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":15000}]'::jsonb,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":15000}]'::jsonb,
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
