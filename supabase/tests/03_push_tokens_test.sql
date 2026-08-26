-- Device tokens: strictly private, and the fan-out skips the author.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

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

insert into members (id, group_id, profile_id, display_name, role) values
  ('44444444-4444-4444-8444-444444444444',
   '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', 'Ravi', 'owner'),
  ('55555555-5555-4555-8555-555555555555',
   '33333333-3333-4333-8333-333333333333',
   '22222222-2222-4222-8222-222222222222', 'Priya', 'member');

insert into device_tokens (token, profile_id, platform) values
  ('token-ravi',  '11111111-1111-4111-8111-111111111111', 'android'),
  ('token-priya', '22222222-2222-4222-8222-222222222222', 'android');

-- Ravi records an expense.
insert into entries (id, group_id, currency, amount_minor, created_by)
values ('88888888-8888-4888-8888-888888888888',
        '33333333-3333-4333-8333-333333333333', 'INR', 240000,
        '44444444-4444-4444-8444-444444444444');
insert into entry_payers (entry_id, member_id, amount_minor)
values ('88888888-8888-4888-8888-888888888888',
        '44444444-4444-4444-8444-444444444444', 240000);
insert into entry_shares (entry_id, member_id, amount_minor) values
  ('88888888-8888-4888-8888-888888888888',
   '44444444-4444-4444-8444-444444444444', 120000),
  ('88888888-8888-4888-8888-888888888888',
   '55555555-5555-4555-8555-555555555555', 120000);
set constraints all immediate;
set constraints all deferred;

-- ---------------------------------------------------------------------------
-- A token is a capability to interrupt someone's phone
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select is((select count(*)::int from device_tokens), 1,
  'you see only your own device tokens');
select is((select token from device_tokens), 'token-ravi',
  'and it is yours');

select throws_ok(
  $$insert into device_tokens (token, profile_id, platform)
    values ('stolen', '22222222-2222-4222-8222-222222222222', 'android')$$,
  '42501', null,
  'you cannot register a token against someone else');

select is(
  (select count(*)::int from device_tokens
    where profile_id = '22222222-2222-4222-8222-222222222222'),
  0,
  'a group member still cannot read another member tokens');

-- ---------------------------------------------------------------------------
-- Fan-out
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select * from tokens_for_entry('88888888-8888-4888-8888-888888888888')$$,
  '42501', null,
  'ordinary users cannot enumerate tokens — only the service role can');

set local role service_role;
select results_eq(
  $$select token from tokens_for_entry('88888888-8888-4888-8888-888888888888')$$,
  $$values ('token-priya')$$,
  'only the other members are woken: never the person who just typed it');

-- ---------------------------------------------------------------------------
-- Registering, including taking a token over
--
-- A device changes hands: somebody signs in as a different account, or
-- reinstalls, and FCM hands back the same registration. The stored row still
-- names the previous owner, and RLS evaluates an upsert's UPDATE half against
-- that row — so a plain upsert is refused and the device silently stops
-- receiving anything. register_device_token is what makes the handover
-- possible, and it can only ever write auth.uid().
-- ---------------------------------------------------------------------------
-- Last, because it deliberately moves a token between accounts and the fan-out
-- assertion above depends on who holds what.
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select lives_ok(
  $$select register_device_token('token-ravi', 'android')$$,
  're-registering your own token is idempotent');

select lives_ok(
  $$select register_device_token('token-priya', 'android')$$,
  'a token held by somebody else can be claimed by the device holding it');

select is(
  (select profile_id from device_tokens where token = 'token-priya'),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'and it now belongs to whoever claimed it');

select throws_ok(
  $$select register_device_token('token-ravi', 'symbian')$$,
  '23514', null,
  'an unknown platform is refused rather than stored');

-- Reading is still nobody else's business: claiming a token you physically
-- hold is not the same as being able to enumerate anyone's.
select is(
  (select count(*)::int from device_tokens
    where profile_id = '22222222-2222-4222-8222-222222222222'),
  0,
  'claiming one grants no visibility of anybody else');

select * from finish();
rollback;
