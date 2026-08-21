-- Exchange rates become server data.
--
-- Three problems with fetching them on the device:
--
--   1. Two clients could show different estimates for the same group, because
--      they fetched at different moments or fell back to different providers.
--      A shared ledger that renders differently on two phones is a support
--      ticket nobody can resolve.
--   2. The rate on an entry was whatever the writing device said it was. It is
--      display-only so it cannot move money, but it is still a number other
--      people read, supplied by a client that can be modified.
--   3. Every device hit a free public endpoint independently, which is both
--      rude and fragile.
--
-- Rates are now fetched once, centrally, by the fetch-fx Edge Function, and
-- reach devices through the ordinary read path.

-- ---------------------------------------------------------------------------
-- The rate table: one row per currency per day, always against USD.
--
-- A pivot rather than a pair table is the whole simplification. Storing pairs
-- means n^2 rows and a question — "do we have INR->AED?" — with a different
-- answer for every combination. Against a single pivot there is exactly one
-- question per currency, and any pair is derived by division:
--
--   A -> B on date D  =  rate(B, D) / rate(A, D)
--
-- So there is no such thing as a supported pair, only a currency we have a
-- rate for, and the FK below makes even that identical to "a currency the app
-- knows how to format".
-- ---------------------------------------------------------------------------
create table fx_rates (
  as_of      date    not null,
  currency   char(3) not null references currencies(code) on delete cascade,

  -- Units of `currency` per one USD. USD itself is stored as exactly 1 so the
  -- pivot needs no special case anywhere.
  rate       numeric(24,10) not null check (rate > 0),

  -- Which provider supplied this row. Rows from one day may come from
  -- different providers, because the waterfall fills gaps rather than stopping
  -- at the first success.
  source     text not null,
  fetched_at timestamptz not null default now(),

  primary key (as_of, currency)
);

create index idx_fx_rates_currency_as_of on fx_rates (currency, as_of desc);

alter table fx_rates enable row level security;

-- Public reference data, exactly like the currencies table. There is
-- deliberately no write policy: only the service role, and therefore only the
-- fetch-fx function, can put a rate in here.
create policy fx_rates_read on fx_rates
  for select to anon, authenticated using (true);

grant select on fx_rates to anon, authenticated;

comment on table fx_rates is
  'ECB and commercial reference rates against USD. Display only: a converted '
  'figure is never a balance, and never stored as one.';

-- ---------------------------------------------------------------------------
-- Providers, as data.
--
-- Which sources to use, in what order, and whether one is switched off is
-- operational — it changes when a provider has an outage, changes terms, or
-- starts wanting a key. None of that should need a code deploy, so it lives in
-- a table the operator can edit. What stays in code is the per-provider
-- parser, because every provider has its own response shape and there is no
-- honest way to make that configuration.
--
-- Adding a provider is therefore: one adapter file, plus one row here.
-- ---------------------------------------------------------------------------
create table fx_providers (
  id               serial primary key,
  name             text    not null unique,

  -- Selects the adapter inside the Edge Function. An unknown kind is skipped
  -- with a warning rather than failing the run, so a row added ahead of its
  -- deploy is harmless.
  kind             text    not null,

  -- Ascending. The waterfall runs in this order and keeps going while any
  -- currency is still missing, so put the most trustworthy source first and
  -- the widest-coverage one after it.
  priority         int     not null,
  enabled          boolean not null default true,

  -- Whether this provider can answer for a past date. Used to skip it when
  -- backfilling rather than wasting a request that will 404.
  supports_history boolean not null default false,

  -- Per-provider settings: base URL, API key reference, and so on.
  config           jsonb   not null default '{}'::jsonb,

  -- Operational visibility. Written by the function on every attempt so a
  -- silently dead provider is visible without reading logs.
  last_attempt_at  timestamptz,
  last_success_at  timestamptz,
  last_error       text
);

alter table fx_providers enable row level security;
-- No policy at all: this is operator configuration, readable and writable
-- only by the service role.

insert into fx_providers (name, kind, priority, supports_history, config) values
  -- ECB reference rates. First because they are an official published source
  -- and because they are the only free one that answers for a past date.
  -- Covers about thirty currencies.
  ('Frankfurter (ECB)', 'frankfurter', 10, true,
   '{"base_url": "https://api.frankfurter.dev"}'::jsonb),

  -- Fills what ECB does not publish — AED, KWD, BHD, LKR, NPR, VND among them,
  -- which between them cover most of where this app is aimed. Latest only on
  -- the free tier.
  ('ExchangeRate-API (open)', 'exchangerate_open', 20, false,
   '{"base_url": "https://open.er-api.com"}'::jsonb);

-- ---------------------------------------------------------------------------
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
-- ---------------------------------------------------------------------------
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

-- Converts between any two currencies on a date, via the pivot.
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

grant execute on function fx_rate_as_of(char(3), date) to anon, authenticated;
grant execute on function fx_convert(char(3), char(3), date) to anon, authenticated;
