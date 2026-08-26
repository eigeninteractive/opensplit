-- Deleting an account: what goes, and what must not.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ravi@example.com', '{"display_name":"Ravi"}', now(), now()),
  ('22222222-2222-4222-8222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'priya@example.com', '{"display_name":"Priya"}', now(), now());

-- A shared group, which must survive Ravi leaving...
insert into groups (id, name, default_currency, created_by)
values ('33333333-3333-4333-8333-333333333333', 'Flat 4B', 'INR',
        '11111111-1111-4111-8111-111111111111');

-- ...and a solo one, which must not: Priya is not in it, and Arun is a
-- placeholder who can never sign in.
insert into groups (id, name, default_currency, created_by)
values ('66666666-6666-4666-8666-666666666666', 'Just me', 'INR',
        '11111111-1111-4111-8111-111111111111');

insert into members (id, group_id, profile_id, display_name) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333',
   '22222222-2222-4222-8222-222222222222', 'Priya'),
  ('77777777-7777-4777-8777-777777777777',
   '66666666-6666-4666-8666-666666666666',
   '11111111-1111-4111-8111-111111111111', 'Ravi'),
  ('88888888-8888-4888-8888-888888888888',
   '66666666-6666-4666-8666-666666666666',
   null, 'Arun');

insert into device_tokens (token, profile_id, platform)
values ('fcm-ravi', '11111111-1111-4111-8111-111111111111', 'android');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
set constraints all deferred;

-- An expense in each group, so neither is the trivially empty case.
select upsert_entry(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '33333333-3333-4333-8333-333333333333', 'INR', 40000,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":40000}]'::jsonb,
  '[{"member_id":"44444444-4444-4444-8444-444444444444","amount_minor":20000},
    {"member_id":"55555555-5555-4555-8555-555555555555","amount_minor":20000}]'::jsonb,
  'Dinner');

select upsert_entry(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '66666666-6666-4666-8666-666666666666', 'INR', 10000,
  '[{"member_id":"77777777-7777-4777-8777-777777777777","amount_minor":10000}]'::jsonb,
  '[{"member_id":"77777777-7777-4777-8777-777777777777","amount_minor":5000},
    {"member_id":"88888888-8888-4888-8888-888888888888","amount_minor":5000}]'::jsonb,
  'Chai');
set constraints all immediate;

-- ---------------------------------------------------------------------------
select lives_ok(
  $$select delete_account()$$,
  'an account can delete itself');

-- Everything below inspects the result rather than exercising a policy, and
-- auth.users is not readable by `authenticated` at all.
reset role;
reset "request.jwt.claims";

select is(
  (select count(*)::int from auth.users
    where id = '11111111-1111-4111-8111-111111111111'),
  0,
  'the account is gone');

select is(
  (select count(*)::int from profiles
    where id = '11111111-1111-4111-8111-111111111111'),
  0,
  'so is the profile it cascades to');

select is(
  (select count(*)::int from device_tokens where token = 'fcm-ravi'),
  0,
  'and the push registration, so a deleted account stops being notified');

-- ---------------------------------------------------------------------------
-- What the co-member is left with
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  1,
  'a group somebody else is still in survives');

select is(
  (select display_name from members
    where id = '44444444-4444-4444-8444-444444444444'),
  'Ravi',
  'the name stays: it is the name a co-member recorded and reads their own '
  'history by');

select is(
  (select profile_id from members
    where id = '44444444-4444-4444-8444-444444444444'),
  null,
  'but the membership is a placeholder now, which is a state this schema '
  'already had a meaning for');

select is(
  (select count(*)::int from entries
    where group_id = '33333333-3333-4333-8333-333333333333'
      and deleted_at is null),
  1,
  'the expense is untouched: it is a fact about Priya''s group too');

select is(
  (select balance_minor::int from v_member_balances
    where member_id = '55555555-5555-4555-8555-555555555555'),
  -20000,
  'and Priya still owes exactly what she owed, which is the whole point of '
  'not erasing the other side of a shared ledger');

select is(
  (select created_by from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  null,
  'the group outlives its creator rather than blocking their deletion');

-- ---------------------------------------------------------------------------
-- What nobody could ever read again
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from groups
    where id = '66666666-6666-4666-8666-666666666666'),
  0,
  'a group with no other account holder is deleted outright: every read '
  'policy goes through a member row with a profile, so leaving it would keep '
  'the expenses forever with nobody alive to read them');

select is(
  (select count(*)::int from entries
    where group_id = '66666666-6666-4666-8666-666666666666'),
  0,
  'along with everything in it');

select * from finish();
rollback;
