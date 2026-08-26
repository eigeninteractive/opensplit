-- Row-level security, and the invite claim flow.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- ---------------------------------------------------------------------------
-- Fixtures: Ravi owns a group with a placeholder for Priya. Zara is a stranger.
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'ravi@example.com', '{"display_name":"Ravi"}', now(), now()),
  ('22222222-2222-4222-8222-222222222222',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'priya@example.com', '{"display_name":"Priya"}', now(), now()),
  ('99999999-9999-4999-8999-999999999999',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'zara@example.com', '{"display_name":"Zara"}', now(), now());

insert into groups (id, name, default_currency, created_by)
values ('33333333-3333-4333-8333-333333333333', 'Goa Trip', 'INR',
        '11111111-1111-4111-8111-111111111111');

insert into members (id, group_id, profile_id, display_name) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333', null, 'Priya');

-- An expense so that the placeholder has a real balance before she ever joins.
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

-- ---------------------------------------------------------------------------
-- A member sees their group
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

-- The classic Supabase failure here is 42P17, infinite recursion: a policy on
-- `members` that itself reads `members`. is_group_member is SECURITY DEFINER
-- precisely so its internal read bypasses RLS and terminates.
select lives_ok(
  $$select count(*) from members
     where group_id = '33333333-3333-4333-8333-333333333333'$$,
  'reading members does not recurse through its own policy');

select is((select count(*)::int from groups), 1, 'Ravi sees his group');
select is((select count(*)::int from members), 2, 'and both members');
select is((select count(*)::int from entries), 1, 'and the expense');
select is((select count(*)::int from v_member_balances), 2,
  'and the balances derived from it');

-- ---------------------------------------------------------------------------
-- A stranger sees nothing
-- ---------------------------------------------------------------------------
set local "request.jwt.claims" to
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}';

select is((select count(*)::int from groups), 0, 'Zara sees no groups');
select is((select count(*)::int from members), 0, 'nor any members');
select is((select count(*)::int from entries), 0, 'nor any entries');
select is((select count(*)::int from v_member_balances), 0,
  'the balances view honours RLS — security_invoker is doing its job');
select is((select count(*)::int from invites), 0, 'nor any invite rows');

-- ---------------------------------------------------------------------------
-- Nobody destroys shared history
--
-- There is no delete policy on groups and no DELETE grant to match. This used
-- to be a narrower rule — owners could, unless the session was anonymous — but
-- nothing in the app has ever deleted a group, and a capability nobody uses is
-- one nobody should have. Archiving is the operation people actually want.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$delete from groups where id = '33333333-3333-4333-8333-333333333333'$$,
  '42501',
  null,
  'a member cannot delete a group, however long they have been in it');

set local role postgres;
select is(
  (select count(*)::int from groups
    where id = '33333333-3333-4333-8333-333333333333'),
  1,
  'and it is still there');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- Issuing an invite
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select create_invite('55555555-5555-4555-8555-555555555555')$$,
  'the owner can issue a link for an unclaimed place');

select throws_ok(
  $$select create_invite('44444444-4444-4444-8444-444444444444')$$,
  '23514', null,
  'but not for a place someone already holds — that is a takeover');

-- ---------------------------------------------------------------------------
-- Redeeming it
--
-- The token is pinned to a known value first, because the person claiming it
-- cannot look it up: they are not in the group, and the invites policy hides
-- the row from them. That is the point — the token travels out of band, in the
-- link, and possession of it is the entire authorisation.
-- ---------------------------------------------------------------------------
set local role postgres;
update invites set token = '00000000-0000-4000-8000-0000000000bb'
 where member_id = '55555555-5555-4555-8555-555555555555';

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from invites
    where token = '00000000-0000-4000-8000-0000000000bb'),
  0,
  'the claimant cannot even read the invite row they are about to spend');

select lives_ok(
  $$select redeem_invite('00000000-0000-4000-8000-0000000000bb')$$,
  'the token alone is enough to claim, with no prior access to the group');

set local role postgres;

select is(
  (select profile_id from members
    where id = '55555555-5555-4555-8555-555555555555'),
  '22222222-2222-4222-8222-222222222222'::uuid,
  'claiming sets exactly one column');

select is(
  (select balance_minor from v_member_balances
    where member_id = '55555555-5555-4555-8555-555555555555'),
  -120000::bigint,
  'and her balance is untouched: she was always a full member');

-- Scoped to the group: this runs as postgres, which bypasses RLS and would
-- otherwise count every entry in the database.
select is(
  (select count(*)::int from entries
    where group_id = '33333333-3333-4333-8333-333333333333'),
  1,
  'no entry was rewritten — this is why members are group-scoped');

select isnt(
  (select redeemed_at from invites
    where member_id = '55555555-5555-4555-8555-555555555555'),
  null, 'the token is spent');

-- ---------------------------------------------------------------------------
-- A spent, expired, or duplicate claim is refused
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}';

select throws_ok(
  $$select redeem_invite('00000000-0000-4000-8000-0000000000bb')$$,
  '23514', null,
  'a single-use token cannot be used twice');

select throws_ok(
  $$select redeem_invite('00000000-0000-4000-8000-0000000000ff')$$,
  'P0002', null,
  'an unknown token is refused');

set local role postgres;
insert into members (id, group_id, profile_id, display_name)
values ('66666666-6666-4666-8666-666666666666',
        '33333333-3333-4333-8333-333333333333', null, 'Arun');
insert into invites (token, group_id, member_id, created_by, expires_at)
values ('00000000-0000-4000-8000-0000000000aa',
        '33333333-3333-4333-8333-333333333333',
        '66666666-6666-4666-8666-666666666666',
        '11111111-1111-4111-8111-111111111111',
        now() - interval '1 day');

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"99999999-9999-4999-8999-999999999999","role":"authenticated"}';

select throws_ok(
  $$select redeem_invite('00000000-0000-4000-8000-0000000000aa')$$,
  '23514', null,
  'an expired link is refused — a forwarded URL must not work forever');

set local role postgres;
update invites set expires_at = now() + interval '1 day'
 where token = '00000000-0000-4000-8000-0000000000aa';

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select throws_ok(
  $$select redeem_invite('00000000-0000-4000-8000-0000000000aa')$$,
  '23505', null,
  'someone already in the group cannot claim a second place');

select * from finish();
rollback;
