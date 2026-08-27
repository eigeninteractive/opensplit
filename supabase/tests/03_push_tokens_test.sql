-- Device tokens: strictly private, and the fan-out skips the author.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

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

-- ---------------------------------------------------------------------------
-- The fan-out is a trigger in this migration, not a row in a dashboard
--
-- A Supabase Database Webhook creates exactly this trigger, calling
-- supabase_functions.http_request(). Declaring it here is what makes it survive
-- a db reset, keeps the secret in app_settings beside fx_fetch_secret, and
-- keeps the whole chain reproducible on a plain Postgres with pg_net.
-- ---------------------------------------------------------------------------
set local role postgres;

select has_trigger('public', 'entries', 'trg_entries_notify',
  'entries carries its own notify trigger, so a deployment fans out without '
  'anybody clicking anything');

-- Every test above ran unconfigured, and so did the expense at the top of this
-- file. That path has to be silent rather than fatal: a deployment with no push
-- set up still records expenses.
select is(
  (select count(*)::int from net.http_request_queue),
  0,
  'with no notify_function_url set, saving an expense queues nothing');

insert into app_settings (key, value) values
  ('notify_function_url',   'http://example.test/functions/v1/notify-entry'),
  ('notify_webhook_secret', 'a-test-secret');

insert into entries (id, group_id, currency, amount_minor, created_by)
values ('99999999-9999-4999-8999-999999999999',
        '33333333-3333-4333-8333-333333333333', 'INR', 50000,
        '44444444-4444-4444-8444-444444444444');
insert into entry_payers (entry_id, member_id, amount_minor)
values ('99999999-9999-4999-8999-999999999999',
        '44444444-4444-4444-8444-444444444444', 50000);
insert into entry_shares (entry_id, member_id, amount_minor)
values ('99999999-9999-4999-8999-999999999999',
        '44444444-4444-4444-8444-444444444444', 50000);
set constraints all immediate;
set constraints all deferred;

select is(
  (select count(*)::int from net.http_request_queue
    where url = 'http://example.test/functions/v1/notify-entry'),
  1,
  'once configured, an expense queues exactly one request');

select is(
  (select headers->>'x-webhook-secret' from net.http_request_queue
    where url = 'http://example.test/functions/v1/notify-entry'),
  'a-test-secret',
  'carrying the secret the function compares in constant time');

-- The reason for building the body by hand rather than sending to_jsonb(new):
-- the description and the notes never leave the database. The device already
-- has to pull the delta, and it is the device that writes the text.
select is(
  (select convert_from(body, 'utf8')::jsonb -> 'record'
     from net.http_request_queue
    where url = 'http://example.test/functions/v1/notify-entry'),
  jsonb_build_object(
    'id',         '99999999-9999-4999-8999-999999999999',
    'group_id',   '33333333-3333-4333-8333-333333333333',
    'created_by', '44444444-4444-4444-8444-444444444444'
  ),
  'and three ids, not the row');

select * from finish();

rollback;
