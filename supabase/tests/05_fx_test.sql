-- Exchange rates: the pivot, the date rule, and who may write them.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                        created_at, updated_at)
values ('11111111-1111-4111-8111-111111111111',
        '00000000-0000-0000-0000-000000000000', 'authenticated',
        'authenticated', 'ravi@example.com', '{"display_name":"Ravi"}',
        now(), now());

-- Hermetic: a real deployment will already hold rates from the scheduled
-- fetch, and this whole file runs inside a transaction that rolls back.
delete from fx_rates;

-- Two publications, and a currency only the second provider carries. This is
-- exactly the shape the waterfall produces.
insert into fx_rates (as_of, currency, rate, source) values
  ('2026-08-14', 'USD', 1,        'Frankfurter (ECB)'),
  ('2026-08-14', 'INR', 95.43,    'Frankfurter (ECB)'),
  ('2026-08-21', 'USD', 1,        'Frankfurter (ECB)'),
  ('2026-08-21', 'INR', 95.70,    'Frankfurter (ECB)'),
  ('2026-08-21', 'AED', 3.6725,   'ExchangeRate-API (open)');

-- ---------------------------------------------------------------------------
-- The date rule
-- ---------------------------------------------------------------------------
select is(fx_rate_as_of('INR', '2026-08-21'), 95.70::numeric,
  'takes the publication for the day when there is one');

select is(fx_rate_as_of('INR', '2026-08-14'), 95.43::numeric,
  'a backdated lookup gets that day''s rate, not the newest');

-- 2026-08-16 was a Sunday. ECB does not publish at weekends, and Friday's rate
-- is the right answer — which needs no calendar logic, only "on or before".
select is(fx_rate_as_of('INR', '2026-08-16'), 95.43::numeric,
  'a weekend falls back to the last publication before it');

select is(fx_rate_as_of('INR', '2026-08-01'), null,
  'never reaches forward for a rate published later');

select is(fx_rate_as_of('XXX', '2026-08-21'), null,
  'a currency with no publication has no rate');

-- ---------------------------------------------------------------------------
-- The pivot
-- ---------------------------------------------------------------------------
select is(fx_convert('USD', 'INR', '2026-08-21'), 95.70::numeric,
  'converting from the pivot is the stored rate itself');

select ok(
  abs(fx_convert('AED', 'INR', '2026-08-21') - (95.70 / 3.6725)) < 0.000001,
  'a pair with neither side the pivot is derived by division');

select is(fx_convert('INR', 'INR', '2026-08-21'), 1::numeric,
  'identity is exactly one, with no division at all');

-- AED has no publication on or before the 14th, so the pair has no answer.
-- Returning today''s rate instead would silently restate history.
select is(fx_convert('AED', 'INR', '2026-08-14'), null,
  'a pair is unanswerable when either side is missing for that date');

-- ---------------------------------------------------------------------------
-- Who may write a rate
-- ---------------------------------------------------------------------------
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select is((select count(*)::int from fx_rates), 5,
  'rates are public reference data, readable by any signed-in user');

-- Display-only or not, a rate is a number other people read, and it comes from
-- the server or not at all.
select throws_ok(
  $$insert into fx_rates (as_of, currency, rate, source)
    values ('2026-08-21', 'INR', 1, 'forged')$$,
  '42501',
  null,
  'a client cannot publish a rate');

select throws_ok(
  $$select count(*) from fx_providers$$,
  '42501',
  null,
  'provider configuration is invisible to users');

-- ---------------------------------------------------------------------------
-- On-demand backfill
--
-- The daily job covers recent dates. This is for an expense backdated past
-- anything we hold, which is exactly when the value is least obvious.
-- ---------------------------------------------------------------------------
-- INR has a rate from the 14th, so nothing before that date can price it.
select ok(request_fx_backfill('2026-08-10', 'INR'),
  'a currency with no rate on or before the date starts a fetch');

select ok(not request_fx_backfill('2026-08-10', 'INR'),
  'asking again the same day does not queue a second fetch');

-- 2026-08-16 was a Sunday, covered by Friday the 14th under "on or before".
-- Chasing a rate that will never exist would burn the ceiling on nothing.
select ok(not request_fx_backfill('2026-08-16', 'INR'),
  'a currency already answerable for that date is not fetched');

select ok(not request_fx_backfill((current_date + 1)::date, 'INR'),
  'a future date has no published rate anywhere');

select ok(not request_fx_backfill('2015-01-05', 'INR'),
  'a date from a decade ago is not an expense anyone is splitting');

select * from finish();
rollback;
