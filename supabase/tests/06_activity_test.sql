-- The activity log, and the dormancy jobs that eventually clear a group away.
begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

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
-- The server writes the record, and only the server writes it. Each row holds
-- what the expense looked like after a change; the feed people read is the
-- difference between consecutive rows, computed by whoever reads them.
--
-- This replaced a client-authored diff, which bought less than it looked. A
-- client could describe its own edit however it liked -- and, worse, could
-- rewrite the shares alone, moving money between members while the total
-- stayed put, and append no history at all.
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

set constraints all immediate;

select is(
  (select count(*)::int from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  1,
  'and recording it writes exactly one snapshot -- not one per row touched, '
  'though the trigger fires once for the entry and once for every payer and '
  'share underneath it');

select is(
  (select actor_id from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  '44444444-4444-4444-8444-444444444444'::uuid,
  'attributed to the caller''s own member row, read from auth.uid() rather '
  'than accepted as a parameter');

select is(
  (select shares from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  '[{"member_id": "44444444-4444-4444-8444-444444444444", "amount_minor": 20000},
    {"member_id": "55555555-5555-4555-8555-555555555555", "amount_minor": 20000}]'::jsonb,
  'carrying who owes what, which is the half the client-authored diff left '
  'out entirely');

-- ---------------------------------------------------------------------------
-- The edit that moves money without moving anything a reader would check
--
-- Priya re-splits the Rs.400 dinner so Ravi owes Rs.300 of it instead of
-- Rs.200. The total is untouched, so the balance invariant is satisfied and
-- nothing on the expense itself looks different.
-- ---------------------------------------------------------------------------
set local "request.jwt.claims" to
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
set constraints all deferred;

select lives_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888',
      '33333333-3333-4333-8333-333333333333', 'INR', 40000,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":40000}]'::jsonb,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":30000},
        {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":10000}]'::jsonb,
      'Dinner')$$,
  'a co-member may re-split an expense: this is an ordinary edit, not '
  'something the schema should refuse');

set constraints all immediate;

select is(
  (select count(*)::int from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  2,
  'but it goes on the record -- a shares-only change is a change, and used to '
  'produce no history whatsoever');

select is(
  (select actor_id from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'
    order by created_at desc limit 1),
  '55555555-5555-4555-8555-555555555555'::uuid,
  'in the name of whoever actually made it');

select is(
  (select shares from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'
    order by created_at desc limit 1),
  '[{"member_id": "44444444-4444-4444-8444-444444444444", "amount_minor": 30000},
    {"member_id": "55555555-5555-4555-8555-555555555555", "amount_minor": 10000}]'::jsonb,
  'showing the split it became, so a reader can watch the hundred rupees move '
  'instead of wondering where it came from');

-- ---------------------------------------------------------------------------
-- Saving something identical is not an event
-- ---------------------------------------------------------------------------
set constraints all deferred;
select upsert_entry(
  '88888888-8888-4888-8888-888888888888',
  '33333333-3333-4333-8333-333333333333', 'INR', 40000,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":40000}]'::jsonb,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":30000},
    {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":10000}]'::jsonb,
  'Dinner');
set constraints all immediate;

select is(
  (select count(*)::int from entry_events
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  2,
  'a re-saved editor and a retried sync add nothing: a feed full of '
  '"Priya edited nothing" is worse than no feed');

-- ---------------------------------------------------------------------------
-- The invariant that makes the duplication safe
-- ---------------------------------------------------------------------------
select is(
  (select (e.description, e.currency, e.amount_minor, e.entry_date,
           e.split_kind, e.category_id, e.notes, e.deleted_at)::text
     from entries e where e.id = '88888888-8888-4888-8888-888888888888'),
  (select (v.description, v.currency, v.amount_minor, v.entry_date,
           v.split_kind, v.category_id, v.notes, v.deleted_at)::text
     from entry_events v
    where v.entry_id = '88888888-8888-4888-8888-888888888888'
    order by v.created_at desc limit 1),
  'the newest snapshot is identical to the live expense, which is what makes '
  'a mismatch a tamper alarm rather than a merge problem');

-- ---------------------------------------------------------------------------
-- There is no second door into the ledger
--
-- Every one of these was reachable, and each of them either moved real money
-- or hid the fact that money had moved.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update entries set amount_minor = 400000
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'an expense cannot be rewritten around upsert_entry, which is where every '
  'check about who may change what lives');

select throws_ok(
  $$update entry_shares set amount_minor = 39000
     where entry_id = '88888888-8888-4888-8888-888888888888'
       and member_id = '44444444-4444-4444-8444-444444444444'$$,
  '42501', null,
  'nor can the split be rewritten underneath it');

select throws_ok(
  $$delete from entry_shares
     where entry_id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'nor can a share simply be dropped');

-- ---------------------------------------------------------------------------
-- The record is readable by the group and writable by nobody
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into entry_events (entry_id, group_id, actor_id, description,
      currency, amount_minor, entry_date, split_kind, payers, shares)
    values ('88888888-8888-4888-8888-888888888888',
            '33333333-3333-4333-8333-333333333333',
            '55555555-5555-4555-8555-555555555555',
            'Dinner', 'INR', 40000, current_date, 'equal', '[]', '[]')$$,
  '42501', null,
  'history cannot be fabricated: with no insert grant there is no '
  'client-authored line left to have to trust');

select throws_ok(
  $$update entry_events set amount_minor = 1$$,
  '42501', null,
  'an audit trail somebody can revise is not one');

select throws_ok(
  $$delete from entry_events$$,
  '42501', null,
  'nor erase one');

-- ---------------------------------------------------------------------------
-- An expense belongs to its group, and to the people in it
-- ---------------------------------------------------------------------------
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
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select throws_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888',
      '66666666-6666-4666-8666-666666666666', 'INR', 100,
      '[{"member_id":"77777777-7777-4777-8777-777777777777","amount_minor":100}]'::jsonb,
      '[{"member_id":"77777777-7777-4777-8777-777777777777","amount_minor":100}]'::jsonb,
      'Hijacked')$$,
  '42501', null,
  'an expense cannot be dragged into another group by naming its id there: '
  'ON CONFLICT does not rewrite group_id, so without an explicit check this '
  'edited a stranger''s expense in place');

reset role;
reset "request.jwt.claims";
insert into groups (id, name, default_currency, created_by)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Ravi only', 'INR',
        '11111111-1111-4111-8111-111111111111');
insert into members (id, group_id, profile_id, display_name)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        '11111111-1111-4111-8111-111111111111', 'Ravi');
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
set constraints all deferred;
select upsert_entry(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'INR', 500,
  '[{"member_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","amount_minor":500}]'::jsonb,
  '[{"member_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","amount_minor":500}]'::jsonb,
  'Ravi''s own');
set constraints all immediate;

set local "request.jwt.claims" to
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select throws_ok(
  format(
    $$select delete_entry(%L::uuid, %L::timestamptz)$$,
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    (select updated_at from entries
      where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')),
  'P0002', null,
  'and cannot be deleted from outside its group: delete_entry carried no '
  'membership test of its own while RLS sat underneath it, and as SECURITY '
  'DEFINER that would have deleted any expense in the database from its id');

-- ---------------------------------------------------------------------------
-- The sync clock belongs to the server
--
-- Run as the owner, because a client cannot reach these columns at all now.
-- The trigger is the guarantee and has to hold on every path, not only on the
-- ones that happen to be closed today.
-- ---------------------------------------------------------------------------
reset role;
reset "request.jwt.claims";

update entries set updated_at = '3000-01-01T00:00:00Z'
 where id = '88888888-8888-4888-8888-888888888888';

select ok(
  (select updated_at < '2100-01-01'::timestamptz from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  'a timestamp in the far future is overwritten with server time: the delta '
  'pull cursors on this column, so one row stamped in the year 3000 pinned '
  'every member''s cursor there and stopped the group syncing permanently');

update entries set updated_at = '2020-01-01T00:00:00Z'
 where id = '88888888-8888-4888-8888-888888888888';

select ok(
  (select updated_at > '2025-01-01'::timestamptz from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  'and so is a backdated one, which otherwise committed a change on the '
  'server that no other device ever received');

-- Profiles carry a cursor too, and it was the one table whose touch trigger
-- fired on UPDATE alone. `authenticated` holds an INSERT grant here and
-- profiles_insert admits your own id, so the insert path is a client-reachable
-- way to set the column the profiles feed cursors on.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values ('99999999-9999-4999-8999-999999999999',
        '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', 'arun@example.com', '{"display_name":"Arun"}',
        now(), now());

delete from profiles where id = '99999999-9999-4999-8999-999999999999';

insert into profiles (id, display_name, updated_at)
values ('99999999-9999-4999-8999-999999999999', 'Arun',
        '3000-01-01T00:00:00Z');

select ok(
  (select updated_at < '2100-01-01'::timestamptz from profiles
    where id = '99999999-9999-4999-8999-999999999999'),
  'a profile inserted with a future timestamp is stamped with server time: '
  'one row in the year 3000 pinned every co-member''s profiles cursor there, '
  'and names and payment handles stopped travelling for good');

update profiles set updated_at = '2020-01-01T00:00:00Z'
 where id = '99999999-9999-4999-8999-999999999999';

select ok(
  (select updated_at > '2025-01-01'::timestamptz from profiles
    where id = '99999999-9999-4999-8999-999999999999'),
  'and a backdated one is too, which would otherwise change a name on the '
  'server that no other device ever fetched');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
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
-- Rs.100, not Rs.200: the re-split above left Priya owing a hundred rupees of
-- the dinner rather than half of it, which is the whole point of that section.
select upsert_entry(
  '99999999-9999-4999-8999-999999999999',
  '33333333-3333-4333-8333-333333333333', 'INR', 10000,
  '[{"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":10000}]'::jsonb,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":10000}]'::jsonb,
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
