-- One rate provider for latest, one for history, and on-demand backfill.
--
-- The keyless ExchangeRate-API endpoint is dropped in favour of the keyed one:
-- same coverage, but a key makes the quota and the caller explicit rather than
-- relying on an unauthenticated public endpoint's goodwill.
delete from fx_providers where kind = 'exchangerate_open';

insert into fx_providers (name, kind, priority, supports_history, config)
values ('ExchangeRate-API', 'exchangerate_v6', 20, false,
        '{"api_key_env": "EXCHANGERATE_API_KEY"}'::jsonb)
on conflict (name) do nothing;

comment on column fx_providers.supports_history is
  'Whether this provider can answer for a past date. ExchangeRate-API''s free '
  'plan cannot — its historical endpoint returns plan-upgrade-required — so it '
  'is skipped when filling a past date and Frankfurter does that alone.';

-- ---------------------------------------------------------------------------
-- Backfill on demand.
--
-- The daily job keeps today topped up, which is all that is needed for a group
-- settling this week's dinners. Backdating an expense to a date we have never
-- fetched is the case it cannot cover, and that is precisely when a rate is
-- least optional: an old expense in another currency is exactly the one whose
-- value is not obvious.
--
-- Once fetched, a rate is kept forever and reaches every device, whether or not
-- the group that prompted it still exists. Rates are app-wide reference data,
-- not per-group state, and a date fetched once is never fetched again.
-- ---------------------------------------------------------------------------
create table fx_backfill_requests (
  as_of        date    not null,
  currency     char(3) not null references currencies(code) on delete cascade,
  requested_at timestamptz not null default now(),
  primary key (as_of, currency)
);

alter table fx_backfill_requests enable row level security;
-- No policy: bookkeeping for the function below, not user-visible.

-- Keyed per currency, not per date.
--
-- A date is never "fully covered": ECB publishes no history for AED, KWD, BHD,
-- LKR, NPR or VND, and no free source does, so a whole-date check would find
-- something missing forever and re-request every old date on a loop. The real
-- question is only ever whether the currency in front of the user can be
-- priced on the day in front of the user.
create or replace function request_fx_backfill(
  p_as_of    date,
  p_currency char(3)
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent int;
begin
  -- A date in the future has no published rate anywhere, and one from a decade
  -- ago is not an expense anybody is splitting.
  if p_as_of > current_date or p_as_of < current_date - interval '5 years' then
    return false;
  end if;

  if not exists (select 1 from currencies where code = p_currency) then
    return false;
  end if;

  -- Already answerable. "On or before" is the lookup rule, so Friday's rate
  -- covers the weekend and there is nothing to fetch.
  if exists (
    select 1 from fx_rates
     where currency = p_currency and as_of <= p_as_of
  ) then
    return false;
  end if;

  -- Tried recently. A day rather than an hour, because the common reason this
  -- comes back empty is that no provider has that history at all — in which
  -- case retrying sooner just burns the ceiling on a question already answered.
  if exists (
    select 1 from fx_backfill_requests
     where as_of = p_as_of
       and currency = p_currency
       and requested_at > now() - interval '1 day'
  ) then
    return false;
  end if;

  -- Global ceiling. Historical fetches go to Frankfurter, which is free and
  -- keyless, so this is politeness to them and a brake on a modified client
  -- rather than quota management.
  select count(*) into v_recent
    from fx_backfill_requests
   where requested_at > now() - interval '1 hour';
  if v_recent >= 20 then
    return false;
  end if;

  insert into fx_backfill_requests (as_of, currency)
  values (p_as_of, p_currency)
      on conflict (as_of, currency) do update set requested_at = now();

  -- One fetch fills every currency it can for that date, not just this one, so
  -- the next question about the same day is usually already answered.
  perform trigger_fx_fetch(jsonb_build_object('as_of', p_as_of::text));
  return true;
end;
$$;

comment on function request_fx_backfill is
  'Asks the server to fetch rates for a date and currency the app has never '
  'needed before. Returns whether a fetch was actually started. Fire and '
  'forget: the rate arrives on a later sync.';

grant execute on function request_fx_backfill(date, char(3)) to authenticated;
