-- Schema shape, the balance invariant, and the write-path RPCs.
--
-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
select is((select count(*)::int from currencies), 16, 'ships 16 currencies');
select is((select exponent from currencies where code = 'INR'), 2::smallint,
  'INR has two decimal places');
select is((select exponent from currencies where code = 'JPY'), 0::smallint,
  'JPY has none — assuming 2 everywhere is a shipped bug');
select is((select exponent from currencies where code = 'KWD'), 3::smallint,
  'KWD has three');

select is((select count(*)::int from categories where group_id is null), 10,
  'ships 10 global category presets');
select ok(
  exists(select 1 from categories
          where id = '00000000-0000-4000-8000-000000000001'
            and name = 'Food & Drink'),
  'preset ids are fixed, so a client can categorise before its first sync');

-- ---------------------------------------------------------------------------
-- Amendments
-- ---------------------------------------------------------------------------
select hasnt_column('public', 'entries', 'receipt_path',
  'receipt_path is gone: storage and egress are what force a paywall');
select has_column('public', 'profiles', 'upi_vpa',
  'payment identity is personal, so it lives on profiles');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ravi@example.com', '{"display_name":"Ravi"}', now(), now()),
  ('22222222-2222-4222-8222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'zara@example.com', '{"display_name":"Zara"}', now(), now());

select is((select display_name from profiles
            where id = '11111111-1111-4111-8111-111111111111'),
  'Ravi', 'a new auth user gets a profile automatically');

-- upi_vpa format constraint
select throws_ok(
  $$update profiles set upi_vpa = 'not a vpa'
     where id = '11111111-1111-4111-8111-111111111111'$$,
  '23514', null, 'a malformed UPI handle is rejected');
select lives_ok(
  $$update profiles set upi_vpa = 'ravi@okhdfcbank'
     where id = '11111111-1111-4111-8111-111111111111'$$,
  'a well-formed UPI handle is accepted');

insert into groups (id, name, default_currency, created_by)
values ('33333333-3333-4333-8333-333333333333', 'Flat 4B', 'INR',
        '11111111-1111-4111-8111-111111111111');

insert into members (id, group_id, profile_id, display_name, role) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi', 'owner'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333', null, 'Priya', 'member');

select is((select profile_id from members
            where id = '55555555-5555-4555-8555-555555555555'),
  null, 'a placeholder is a full member with no account');

-- A second group, to prove members cannot cross group boundaries.
insert into groups (id, name, default_currency, created_by)
values ('66666666-6666-4666-8666-666666666666', 'Other', 'INR',
        '11111111-1111-4111-8111-111111111111');
insert into members (id, group_id, profile_id, display_name)
values ('77777777-7777-4777-8777-777777777777',
        '66666666-6666-4666-8666-666666666666', null, 'Outsider');

-- ---------------------------------------------------------------------------
-- The invariant
-- ---------------------------------------------------------------------------
create function pg_temp.write_entry(
  p_amount bigint, p_paid bigint, p_owed_a bigint, p_owed_b bigint
) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into entries (id, group_id, currency, amount_minor, created_by)
  values (v_id, '33333333-3333-4333-8333-333333333333', 'INR', p_amount,
          '44444444-4444-4444-8444-444444444444');
  insert into entry_payers (entry_id, member_id, amount_minor)
  values (v_id, '44444444-4444-4444-8444-444444444444', p_paid);
  insert into entry_shares (entry_id, member_id, amount_minor, weight) values
    (v_id, '44444444-4444-4444-8444-444444444444', p_owed_a, 1),
    (v_id, '55555555-5555-4555-8555-555555555555', p_owed_b, 1);
  -- The trigger is deferrable initially deferred, so it would otherwise not
  -- fire until COMMIT. Forcing it here is what makes it testable at all.
  set constraints all immediate;
end $$;

select lives_ok(
  $$select pg_temp.write_entry(2400, 2400, 1200, 1200)$$,
  'a balanced entry is accepted');

select throws_ok(
  $$select pg_temp.write_entry(2400, 2400, 1200, 1199)$$,
  '23514', null,
  'shares that fall a paisa short are rejected at commit');

select throws_ok(
  $$select pg_temp.write_entry(2400, 2399, 1200, 1200)$$,
  '23514', null,
  'payers that fall a paisa short are rejected at commit');

select throws_ok(
  $$select pg_temp.write_entry(2400, 2400, 1200, 1201)$$,
  '23514', null,
  'shares that overshoot are rejected too');

-- Members must belong to the entry's group.
select throws_ok(
  $$insert into entry_shares (entry_id, member_id, amount_minor)
    select id, '77777777-7777-4777-8777-777777777777', 1 from entries limit 1$$,
  '23503', null,
  'a share cannot name a member of a different group');

-- ---------------------------------------------------------------------------
-- Balances are a view, and they sum to zero
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(sum(balance_minor), 0)::bigint from v_member_balances
    where group_id = '33333333-3333-4333-8333-333333333333'),
  0::bigint,
  'balances sum to exactly zero per group');

select is(
  (select balance_minor from v_member_balances
    where member_id = '44444444-4444-4444-8444-444444444444'),
  1200::bigint,
  'the payer is in credit for what the others owe');

-- ---------------------------------------------------------------------------
-- The write path
-- ---------------------------------------------------------------------------
-- SET CONSTRAINTS is transaction-scoped, and the invariant tests above left it
-- IMMEDIATE. Restore the deferred behaviour the real write path relies on:
-- upsert_entry inserts the entry, then payers, then shares, and is only
-- balanced once all three have landed.
set constraints all deferred;

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select lives_ok($$
  select upsert_entry(
    '88888888-8888-4888-8888-888888888888'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    'INR', 90000,
    '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":90000}]'::jsonb,
    '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":45000,"weight":1},
      {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":45000,"weight":1}]'::jsonb,
    'Groceries')
$$, 'upsert_entry writes an entry with its payers and shares');

select is(
  (select description from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  'Groceries', 'the entry landed');

-- Re-running with different content must update, not silently discard. The
-- first version of this RPC only touched description on conflict.
select lives_ok($$
  select upsert_entry(
    '88888888-8888-4888-8888-888888888888'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    'INR', 120000,
    '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":120000}]'::jsonb,
    '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":60000,"weight":1},
      {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":60000,"weight":1}]'::jsonb,
    'Groceries and drinks')
$$, 'upsert_entry is idempotent on the primary key');

select is(
  (select amount_minor from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  120000::bigint, 'the edit actually replaced the amount');

select is(
  (select count(*)::int from entry_shares
    where entry_id = '88888888-8888-4888-8888-888888888888'),
  2, 'children were replaced, not duplicated');

-- Soft delete only.
select lives_ok(
  $$select delete_entry('88888888-8888-4888-8888-888888888888')$$,
  'delete_entry soft-deletes and returns the row');

select isnt(
  (select deleted_at from entries
    where id = '88888888-8888-4888-8888-888888888888'),
  null, 'the row is still there, marked deleted');

select throws_ok(
  $$delete from entries where id = '88888888-8888-4888-8888-888888888888'$$,
  '42501', null,
  'a hard delete is impossible: it would vanish from every delta feed');

select * from finish();
rollback;
