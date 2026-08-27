-- What a modified client can and cannot do.
--
-- The app computes splits on the device and sends the result, so the honest
-- question is not "is the client trusted" — it is not — but "what exactly does
-- the server refuse". Every test here is an attack a hand-rolled HTTP call
-- could attempt against a real deployment with a valid session.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

-- ---------------------------------------------------------------------------
-- Two groups that share nothing. Ravi owns Goa; Zara owns Manali.
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ravi@example.com', '{"display_name":"Ravi"}', now(), now()),
  ('99999999-9999-4999-8999-999999999999',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'zara@example.com', '{"display_name":"Zara"}', now(), now());

insert into groups (id, name, default_currency, created_by) values
  ('33333333-3333-4333-8333-333333333333', 'Goa Trip', 'INR',
   '11111111-1111-4111-8111-111111111111'),
  ('a3333333-3333-4333-8333-333333333333', 'Manali', 'INR',
   '99999999-9999-4999-8999-999999999999');

insert into members (id, group_id, profile_id, display_name) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333', null, 'Priya'),
  ('a4444444-4444-4444-8444-444444444444',
   'a3333333-3333-4333-8333-333333333333',
   '99999999-9999-4999-8999-999999999999', 'Zara');

insert into entries (id, group_id, currency, amount_minor, created_by)
values ('88888888-8888-4888-8888-888888888888',
        '33333333-3333-4333-8333-333333333333', 'INR', 240000,
        '44444444-4444-4444-8444-444444444444');
insert into entry_payers (entry_id, member_id, amount_minor)
values ('88888888-8888-4888-8888-888888888888',
        '44444444-4444-4444-8444-444444444444', 240000);
insert into entry_shares (entry_id, member_id, amount_minor, weight) values
  ('88888888-8888-4888-8888-888888888888',
   '44444444-4444-4444-8444-444444444444', 120000, 1),
  ('88888888-8888-4888-8888-888888888888',
   '55555555-5555-4555-8555-555555555555', 120000, 1);
set constraints all immediate;
set constraints all deferred;

-- ===========================================================================
-- A stranger with a perfectly valid session
-- ===========================================================================
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}';

select is(
  (select count(*)::int from entries
    where group_id = '33333333-3333-4333-8333-333333333333'),
  0,
  'a non-member reads none of another group''s entries');

select throws_ok(
  $$insert into entries (group_id, currency, amount_minor, created_by)
    values ('33333333-3333-4333-8333-333333333333', 'INR', 100,
            '44444444-4444-4444-8444-444444444444')$$,
  '42501',
  null,
  'a non-member cannot write an entry into another group -- and since the '
  'grants went, neither can a member: the ledger takes no direct writes at '
  'all');

-- The interesting one: reuse a known entry id but claim it belongs to a group
-- the attacker really is in, so that is_group_member() passes. The upsert then
-- takes the ON CONFLICT path against a row in the victim's group.
select throws_ok(
  $$select upsert_entry(
      '88888888-8888-4888-8888-888888888888'::uuid,
      'a3333333-3333-4333-8333-333333333333'::uuid,
      'INR'::char(3), 1::bigint,
      '[{"member_id":"a4444444-4444-4444-8444-444444444444","amount_minor":1}]'::jsonb,
      '[{"member_id":"a4444444-4444-4444-8444-444444444444","amount_minor":1}]'::jsonb)$$,
  null,
  null,
  'an entry in another group cannot be hijacked by upserting its id');

-- Read it back as someone entitled to see it: Zara cannot, which is the point.
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is(
  (select amount_minor from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  240000::bigint,
  'and the victim entry is untouched');

-- ===========================================================================
-- A real member, talking to PostgREST instead of calling the RPC
--
-- This used to be the interesting section. `authenticated` held INSERT, UPDATE
-- and DELETE on entries, entry_payers and entry_shares -- upsert_entry was
-- SECURITY INVOKER and could not work without them -- so every attack below
-- was one plain HTTP call away and the schema had to catch each on its own.
--
-- It holds none of them now. Both RPCs are SECURITY DEFINER and carry their
-- own privileges, so the ledger has exactly one door. This section tests that
-- the wall is a wall; the next tests the guarantees behind it, which still
-- have to hold because the RPC is now a privileged writer.
-- ===========================================================================
select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 0)$$,
  '42501', null,
  'a share cannot be written directly at all, whoever it names');

select throws_ok(
  $$insert into entry_payers (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 1)$$,
  '42501', null,
  'nor a payer');

select throws_ok(
  $$update entry_shares set amount_minor = 1
     where entry_id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'nor can an existing split be rewritten -- the edit that moves money '
  'between members while the total stays put, which the balance invariant '
  'accepts and no client-authored history ever mentioned');

select throws_ok(
  $$update entries set amount_minor = 999999999
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'nor an amount, around the one function that records that it changed');

select throws_ok(
  $$delete from entries where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'and an expense can no more be hard-deleted than it ever could');

-- created_by is taken from auth.uid(), never from the caller's arguments:
-- there is no parameter for it at all.
select is(
  (select created_by from upsert_entry(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      '33333333-3333-4333-8333-333333333333'::uuid,
      'INR'::char(3), 1000::bigint,
      '[{"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":1000}]'::jsonb,
      '[{"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":1000}]'::jsonb)),
  '44444444-4444-4444-8444-444444444444'::uuid,
  'authorship is the caller''s own member row, not anything they can supply');

-- ===========================================================================
-- The guarantees behind the wall
--
-- Run with the owner's privileges but the caller's claims still set, which is
-- the only way to reach these now: the grants stop an `authenticated` session
-- before any of them, and guard_entry_write returns early when auth.uid() is
-- null, so an unauthenticated owner would skip the very checks under test.
--
-- Worth reaching. upsert_entry is a privileged writer today, so "no client can
-- get here" is not an answer -- these are what stand between a bug in the one
-- remaining write path and a ledger that does not add up.
-- ===========================================================================
reset role;
set constraints all deferred;

select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 0)$$,
  '23503', null,
  'a share still cannot name a member of a different group');

select throws_ok(
  $$insert into entry_payers (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 1)$$,
  '23503', null,
  'nor can a payer');

select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            '55555555-5555-4555-8555-555555555555', -500)$$,
  '23514', null,
  'and a negative share still cannot manufacture a debt');

select throws_ok(
  $$update entries set created_by = '55555555-5555-4555-8555-555555555555'
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'authorship cannot be reassigned by writing to the column');

select throws_ok(
  $$update entries set group_id = '66666666-6666-4666-8666-666666666666'
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'an expense cannot be moved into another group, stranding its own payers '
  'and shares in the one it left');

select throws_ok(
  $$insert into entries (group_id, currency, amount_minor, created_by)
    values ('33333333-3333-4333-8333-333333333333', 'INR', 100,
            '55555555-5555-4555-8555-555555555555')$$,
  '42501', null,
  'and an expense cannot be recorded under another member''s name');

-- Both of the next two are the balance invariant, reached without touching a
-- payer or a share -- which is exactly why hanging it off the children alone
-- was not enough.
savepoint restated;
update entries set amount_minor = 999999999
 where id = '88888888-8888-4888-8888-888888888888';
select throws_ok(
  'set constraints all immediate',
  '23514', null,
  'the stated amount cannot be restated away from what was paid and owed');
rollback to savepoint restated;
set constraints all deferred;

savepoint childless;
insert into entries (id, group_id, currency, amount_minor, created_by)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff',
        '33333333-3333-4333-8333-333333333333', 'INR', 500000,
        '44444444-4444-4444-8444-444444444444');
select throws_ok(
  'set constraints all immediate',
  '23514', null,
  'an expense with no payers or shares at all does not balance either');
rollback to savepoint childless;

set local role authenticated;
set constraints all deferred;

-- The legitimate path is untouched by all of the above.
select lives_ok(
  $$select upsert_entry(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      '33333333-3333-4333-8333-333333333333'::uuid,
      'INR'::char(3), 30000::bigint,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":30000}]'::jsonb,
      '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":15000},
        {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":15000}]'::jsonb)$$,
  'and upsert_entry still records an expense normally');

-- The invariant, checked at COMMIT.
--
-- As the owner, like the other table guarantees above: `authenticated` cannot
-- write these rows at all any more, and this has to hold for the privileged
-- writer that can.
reset role;
savepoint unbalanced;
insert into entries (id, group_id, currency, amount_minor, created_by)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        '33333333-3333-4333-8333-333333333333', 'INR', 100000,
        '44444444-4444-4444-8444-444444444444');
insert into entry_payers (entry_id, member_id, amount_minor)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        '44444444-4444-4444-8444-444444444444', 100000);
insert into entry_shares (entry_id, member_id, amount_minor) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   '44444444-4444-4444-8444-444444444444', 40000),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   '55555555-5555-4555-8555-555555555555', 40000);
select throws_ok(
  'set constraints all immediate',
  '23514',
  null,
  'shares that do not sum to the amount are refused at commit');
rollback to savepoint unbalanced;
set constraints all deferred;

-- ===========================================================================
-- Exchange rates
--
-- fx_rate is display-only and never folds into a balance, so a poisoned value
-- cannot move money. It can still make another member's converted estimate
-- nonsense, which is worth refusing on its own.
--
-- Still as the owner, and for the same reason: these are CHECK constraints on
-- the table, and what has to be proved is that the column cannot hold nonsense
-- however it is written.
-- ===========================================================================
select throws_ok(
  $$insert into entries (id, group_id, currency, amount_minor, created_by,
                         fx_rate)
    values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            '33333333-3333-4333-8333-333333333333', 'USD', 100,
            '44444444-4444-4444-8444-444444444444', -5)$$,
  '23514',
  null,
  'a negative exchange rate is refused');

select throws_ok(
  $$insert into entries (id, group_id, currency, amount_minor, created_by,
                         fx_rate)
    values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
            '33333333-3333-4333-8333-333333333333', 'USD', 100,
            '44444444-4444-4444-8444-444444444444', 0)$$,
  '23514',
  null,
  'a zero exchange rate is refused');

set local role authenticated;

-- ===========================================================================
-- Inside the group: what one member can do to another
--
-- The policy on `members` admits any member of a group to update any member
-- row of that group, and it cannot do better — a policy cannot say "this
-- column, but only on your own row", and its WITH CHECK cannot see OLD at all.
-- Every one of the first five below was reachable until guard_member_update()
-- existed, and the second of them redirects real money.
-- ===========================================================================
reset role;

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values ('77777777-7777-4777-8777-777777777777',
        '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', 'kabir@example.com', '{"display_name":"Kabir"}',
        now(), now());

-- Kabir holds an account and is an ordinary member. Priya is still a
-- placeholder, and the difference between them is exactly what the rules
-- turn on: a placeholder has to stay editable by the group, because somebody
-- has to be able to name and pay a person who has never opened the app.
insert into members (id, group_id, profile_id, display_name)
values ('66666666-6666-4666-8666-666666666666',
        '33333333-3333-4333-8333-333333333333',
        '77777777-7777-4777-8777-777777777777', 'Kabir');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}';

select throws_ok(
  $$update members set upi_vpa = 'attacker@okaxis'
     where id = '44444444-4444-4444-8444-444444444444'$$,
  '42501',
  null,
  'a member cannot redirect another member''s settle-up handle');

select throws_ok(
  $$update members set profile_id = null
     where id = '44444444-4444-4444-8444-444444444444'$$,
  '42501',
  null,
  'a member cannot evict another by blanking their profile');

select throws_ok(
  $$update members set display_name = 'Not Ravi'
     where id = '44444444-4444-4444-8444-444444444444'$$,
  '42501',
  null,
  'a member cannot rename another account holder');

select throws_ok(
  $$update members set left_at = now()
     where id = '44444444-4444-4444-8444-444444444444'$$,
  '42501',
  null,
  'a member cannot mark somebody else as having left');

select throws_ok(
  $$update members set group_id = 'a3333333-3333-4333-8333-333333333333'
     where id = '66666666-6666-4666-8666-666666666666'$$,
  '42501',
  null,
  'a member cannot carry themselves into another group');

-- ---------------------------------------------------------------------------
-- And everything the app legitimately does, which all of the above must not
-- have cost. A guard that also blocks the product is not a fix.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$update members set display_name = 'Priya S', upi_vpa = 'priya@okhdfcbank'
     where id = '55555555-5555-4555-8555-555555555555'$$,
  'a placeholder stays editable by anyone in the group');

select lives_ok(
  $$update members set upi_vpa = 'kabir@oksbi'
     where id = '66666666-6666-4666-8666-666666666666'$$,
  'your own payment handle stays yours to set');

-- Last, because it ends Kabir's membership and with it his access.
select lives_ok(
  $$update members set left_at = now()
     where id = '66666666-6666-4666-8666-666666666666'$$,
  'you can always leave of your own accord');

set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

-- ===========================================================================
-- Equal members, and the one asymmetry left
--
-- There is no owner. What an owner used to gate is now either everybody's or
-- nobody's, with one exception: you may remove somebody else only once the
-- group is square with them.
-- ===========================================================================
select lives_ok(
  $$update groups set name = 'Flat 4B, renamed'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  'any member can rename the group — it touches no money, and anybody who '
  'disagrees can rename it back');

select throws_ok(
  $$delete from groups where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501',
  null,
  'but nobody can delete one, however long they have been in it');

-- Removing somebody does not only remove them: is_group_member requires
-- left_at is null, so it cuts off their read access too — and the member most
-- worth cutting off is the one still owed money.
select throws_ok(
  $$update members set left_at = now()
     where id = '55555555-5555-4555-8555-555555555555'$$,
  '42501',
  null,
  'an unsettled member cannot be removed by somebody else');

insert into members (id, group_id, profile_id, display_name)
values ('b6666666-6666-4666-8666-666666666666',
        '33333333-3333-4333-8333-333333333333', null, 'Nobody');

select lives_ok(
  $$update members set left_at = now()
     where id = 'b6666666-6666-4666-8666-666666666666'$$,
  'a settled one can be: with nothing owed either way it is just tidying up');

-- ===========================================================================
-- groups.created_by is a permission, not a description
--
-- Every policy on groups and members reads `is_group_member(...) OR
-- is_group_creator(...)`, so whoever this column names holds an alternative to
-- membership. groups_update let any member write it, which made the second
-- half of that condition assignable — see guard_group_update().
-- ===========================================================================
set local role postgres;
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('c1111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ishan@example.com', '{"display_name":"Ishan"}', now(), now()),
  ('c2222222-2222-4222-8222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'mallory@example.com', '{"display_name":"Mallory"}', now(), now());

-- Ishan is an ordinary member of Ravi's group. Mallory is in no group at all.
insert into members (id, group_id, profile_id, display_name)
values ('c3333333-3333-4333-8333-333333333333',
        '33333333-3333-4333-8333-333333333333',
        'c1111111-1111-4111-8111-111111111111', 'Ishan');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated"}';

select throws_ok(
  $$update groups set created_by = 'c1111111-1111-4111-8111-111111111111'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501', null,
  'a member cannot make themselves the creator — which would survive their '
  'own removal and let them rejoin at will');

select throws_ok(
  $$update groups set created_by = 'c2222222-2222-4222-8222-222222222222'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501', null,
  'nor hand it to an account that has never been in the group, which '
  'members_insert would then let add itself');

select throws_ok(
  $$update groups set created_at = now() - interval '20 years'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501', null,
  'nor back-date the group into the dormancy purge ahead of time');

-- The legitimate paths, which all of the above must leave alone.
select lives_ok(
  $$update groups set name = 'Renamed by a member who did not create it'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  'a member who did not create the group can still rename it');

-- The client upserts the whole row on every push, so it re-sends both guarded
-- columns every time. Echoing a value is not rewriting it, and if it were,
-- every rename by a non-creator would dead-letter.
select lives_ok(
  $$update groups
       set name       = 'Renamed again, echoing the row back',
           created_by = '11111111-1111-4111-8111-111111111111',
           created_at = (select created_at from groups
                          where id = '33333333-3333-4333-8333-333333333333')
     where id = '33333333-3333-4333-8333-333333333333'$$,
  'and re-sending the same created_by and created_at is not a rewrite');

-- Not an owner power either: the column is fixed at insert for everybody.
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select throws_ok(
  $$update groups set created_by = 'c1111111-1111-4111-8111-111111111111'
     where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501', null,
  'and the genuine creator cannot pass it on either');

select * from finish();

rollback;
