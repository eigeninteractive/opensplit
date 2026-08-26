-- What a modified client can and cannot do.
--
-- The app computes splits on the device and sends the result, so the honest
-- question is not "is the client trusted" — it is not — but "what exactly does
-- the server refuse". Every test here is an attack a hand-rolled HTTP call
-- could attempt against a real deployment with a valid session.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

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
  'a non-member cannot write an entry into another group');

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
-- A real member, doing things the UI would never ask for
-- ===========================================================================
select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 0)$$,
  '23503',
  null,
  'a share cannot name a member of a different group');

select throws_ok(
  $$insert into entry_payers (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            'a4444444-4444-4444-8444-444444444444', 1)$$,
  '23503',
  null,
  'a payer cannot name a member of a different group');

select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    values ('88888888-8888-4888-8888-888888888888',
            '55555555-5555-4555-8555-555555555555', -500)$$,
  '23514',
  null,
  'a negative share cannot manufacture a debt');

select throws_ok(
  $$delete from entries where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501',
  null,
  'not even a group owner can hard-delete an entry');

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

-- ---------------------------------------------------------------------------
-- Writing to entries directly, without going through upsert_entry.
--
-- `authenticated` holds INSERT and UPDATE on entries because upsert_entry is
-- SECURITY INVOKER and needs them, so none of this needs anything more than a
-- client that talks to PostgREST instead of calling the RPC. All five of these
-- committed before guard_entry_write and trg_entries_balanced existed.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update entries set created_by = '55555555-5555-4555-8555-555555555555'
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'authorship cannot be reassigned by writing to the column directly');

select throws_ok(
  $$update entries set group_id = '66666666-6666-4666-8666-666666666666'
     where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'an expense cannot be moved into another group, stranding its own '
  'payers and shares in the one it left');

select throws_ok(
  $$insert into entries (group_id, currency, amount_minor, created_by)
    values ('33333333-3333-4333-8333-333333333333', 'INR', 100,
            '55555555-5555-4555-8555-555555555555')$$,
  '42501', null,
  'an expense cannot be recorded under another member''s name');

-- Both of the next two are the balance invariant, reached without touching a
-- payer or a share — which is exactly why hanging it off the children alone
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

select * from finish();
rollback;
