-- ============================================================================
-- Exchange rates.
--
-- Fetched by the server, never by devices. Three reasons:
--
--   1. Two clients fetching independently could show different estimates for
--      the same group. A shared ledger that renders differently on two phones
--      is a support ticket nobody can resolve.
--   2. A rate is a number other people read. It should not be supplied by a
--      client that can be modified, display-only or not.
--   3. Every device hitting a free public endpoint is both rude and fragile.
--
-- Rates are display only. A converted figure is never a balance and never
-- stored as one — balances stay authoritative per currency, because an
-- exchange rate is an opinion and a debt is not.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- One row per currency per day, always against USD.
--
-- A pivot rather than a pair table is the whole simplification. Pairs mean n^2
-- rows and a question — "do we have INR to AED?" — with a different answer for
-- every combination. Against a single pivot there is one question per currency,
-- and any pair is derived by division:
--
--   A -> B on date D  =  rate(B, D) / rate(A, D)
--
-- So there is no such thing as a supported pair, only a currency we have a rate
-- for; and the FK below makes even that identical to "a currency the app knows
-- how to format".
-- ----------------------------------------------------------------------------
create table fx_rates (
  as_of      date    not null,
  currency   char(3) not null references currencies(code) on delete cascade,

  -- Units of `currency` per one USD. USD itself is stored as exactly 1 so the
  -- pivot needs no special case anywhere.
  rate       numeric(24,10) not null check (rate > 0),

  -- Which provider supplied this row. Rows for one day can come from different
  -- providers, because the waterfall fills gaps rather than stopping at the
  -- first success.
  source     text not null,
  fetched_at timestamptz not null default now(),

  primary key (as_of, currency)
);

create index idx_fx_rates_currency_as_of on fx_rates (currency, as_of desc);

alter table fx_rates enable row level security;

comment on table fx_rates is
  'ECB and commercial reference rates against USD. Display only: a converted '
  'figure is never a balance, and never stored as one.';

-- ----------------------------------------------------------------------------
-- Providers, as data.
--
-- Which sources to use, in what order, and whether one is switched off is
-- operational — it changes when a provider has an outage, changes terms, or
-- starts wanting a key. None of that should need a code deploy, so it lives in
-- a table the operator can edit. What stays in code is the per-provider parser,
-- because every provider has its own response shape and there is no honest way
-- to make that configuration.
--
-- Adding a provider is therefore: one adapter file, plus one row here.
-- ----------------------------------------------------------------------------
create table fx_providers (
  id               serial primary key,
  name             text    not null unique,

  -- Selects the adapter inside the Edge Function. An unknown kind is skipped
  -- with a warning rather than failing the run, so a row added ahead of its
  -- deploy is harmless.
  kind             text    not null,

  -- Ascending. The waterfall runs in this order and keeps going while any
  -- currency is still missing, so the most trustworthy source goes first and
  -- the widest-coverage one after it.
  priority         int     not null,
  enabled          boolean not null default true,

  -- Whether this provider can answer for a past date. Used to skip it when
  -- backfilling rather than spending a request that will be refused.
  supports_history boolean not null default false,

  -- Per-provider settings: base URL, the name of the environment secret holding
  -- its API key, and so on. The key itself is never stored here.
  config           jsonb   not null default '{}'::jsonb,

  -- Operational visibility, written on every attempt so a silently dead
  -- provider is apparent without reading function logs.
  last_attempt_at  timestamptz,
  last_success_at  timestamptz,
  last_error       text
);

alter table fx_providers enable row level security;
-- No policy at all: operator configuration, reachable only by the service role.

comment on column fx_providers.supports_history is
  'Whether this provider can answer for a past date. ExchangeRate-API''s free '
  'plan cannot — its historical endpoint returns plan-upgrade-required — so it '
  'is skipped when filling a past date and Frankfurter does that alone.';

insert into fx_providers (name, kind, priority, supports_history, config) values
  -- ECB reference rates. First because they are an official published source,
  -- and because they are the only free one that answers for a past date.
  -- Covers about thirty currencies.
  ('Frankfurter (ECB)', 'frankfurter', 10, true,
   '{"base_url": "https://api.frankfurter.dev"}'::jsonb),

  -- Fills what ECB does not publish — AED, KWD, BHD, LKR, NPR and VND among
  -- them, which between them cover most of where this app is aimed. Latest
  -- only: the free plan's historical endpoint answers plan-upgrade-required.
  ('ExchangeRate-API', 'exchangerate_v6', 20, false,
   '{"api_key_env": "EXCHANGERATE_API_KEY"}'::jsonb);

-- ----------------------------------------------------------------------------
-- Rate lookup.
--
-- "The rate as of a date" means the most recent publication on or before it,
-- never a later one. Backdating an expense to last Tuesday must use last
-- Tuesday's rate; using today's would silently restate history every time the
-- market moved.
--
-- This also removes weekends and holidays as a special case. ECB publishes on
-- business days only, so a Sunday has no row and the Friday one is the correct
-- answer — which is exactly what "most recent on or before" returns, with no
-- calendar logic anywhere.
-- ----------------------------------------------------------------------------
create or replace function fx_rate_as_of(p_currency char(3), p_as_of date)
returns numeric
language sql
stable
set search_path = public
as $$
  select rate
    from fx_rates
   where currency = p_currency
     and as_of <= p_as_of
   order by as_of desc
   limit 1;
$$;

comment on function fx_rate_as_of is
  'Units of p_currency per USD, as most recently published on or before '
  'p_as_of. Null when nothing has ever been published for it.';

create or replace function fx_convert(
  p_from  char(3),
  p_to    char(3),
  p_as_of date
)
returns numeric
language sql
stable
set search_path = public
as $$
  select case
    when p_from = p_to then 1::numeric
    else (
      select fx_rate_as_of(p_to, p_as_of) / nullif(fx_rate_as_of(p_from, p_as_of), 0)
    )
  end;
$$;

comment on function fx_convert is
  'Multiplier to convert p_from into p_to as of p_as_of. Null when either side '
  'has no published rate. Display only.';

-- ----------------------------------------------------------------------------
-- Asking the fetcher to run.
--
-- The fetch itself is an Edge Function, so Postgres reaches it over HTTP. The
-- URL and shared secret are deployment facts and do not belong in a migration,
-- so they live in a settings table and this no-ops until they are set — a
-- deployment that never configures rates still applies cleanly and simply shows
-- no converted estimates.
-- ----------------------------------------------------------------------------
create table app_settings (
  key   text primary key,
  value text not null
);

alter table app_settings enable row level security;
-- No policy: service role only. Nothing here is any user's business.

comment on table app_settings is
  'Operator configuration. Set fx_function_url and fx_fetch_secret to enable '
  'the scheduled exchange-rate fetch.';

-- Fire and forget: pg_net queues the request and returns immediately, so a slow
-- or dead rate provider can never hold a database transaction open.
create or replace function trigger_fx_fetch(p_body jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url    text;
  v_secret text;
begin
  select value into v_url    from app_settings where key = 'fx_function_url';
  select value into v_secret from app_settings where key = 'fx_fetch_secret';

  if v_url is null or v_secret is null then
    raise notice 'fx fetch is not configured; skipping';
    return;
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net is not installed; skipping';
    return;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-fx-secret',  v_secret
    ),
    body    := p_body
  );
end;
$$;

comment on function trigger_fx_fetch is
  'Posts to the fetch-fx Edge Function. Pass {"backfill_days": N} to fill gaps.';

-- ----------------------------------------------------------------------------
-- Backfill on demand.
--
-- The daily job keeps today topped up, which is all a group settling this
-- week's dinners needs. Backdating an expense to a date never fetched is the
-- case it cannot cover, and that is precisely when a rate is least optional: an
-- old expense in another currency is exactly the one whose value is not obvious.
--
-- Once fetched, a rate is kept forever and reaches every device, whether or not
-- the group that prompted it still exists. Rates are app-wide reference data,
-- not per-group state, and a date fetched once is never fetched again.
-- ----------------------------------------------------------------------------
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
-- A date is never "fully covered": no free source has AED, KWD, BHD, LKR, NPR
-- or VND history, so a whole-date check would find something missing forever and
-- re-request every old date on a loop. The real question is only ever whether
-- the currency in front of the user can be priced on the day in front of them.
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
