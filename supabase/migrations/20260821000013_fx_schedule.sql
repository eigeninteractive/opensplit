-- Scheduling for the rate fetch.
--
-- The job posts to the fetch-fx Edge Function. It needs a URL and the shared
-- secret, neither of which belongs in a migration, so they live in a
-- service-role-only settings table and the job no-ops until they are set. A
-- deployment that never configures rates therefore still applies cleanly and
-- simply shows no converted estimates.

create table app_settings (
  key   text primary key,
  value text not null
);

alter table app_settings enable row level security;
-- No policy: service role only. There is nothing here any user should read.

comment on table app_settings is
  'Operator configuration. Set fx_function_url and fx_fetch_secret to enable '
  'the scheduled exchange-rate fetch.';

-- ---------------------------------------------------------------------------
-- Asks the Edge Function to refresh rates.
--
-- Fire-and-forget: pg_net queues the request and returns immediately, so a slow
-- or dead rate provider can never hold a database transaction open.
-- ---------------------------------------------------------------------------
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

revoke execute on function trigger_fx_fetch(jsonb) from public, anon, authenticated;

comment on function trigger_fx_fetch is
  'Posts to the fetch-fx Edge Function. Pass {"backfill_days": N} to fill gaps.';

-- ---------------------------------------------------------------------------
-- Daily, at 16:30 UTC.
--
-- ECB publishes around 16:00 CET, which is 14:00 or 15:00 UTC depending on the
-- season, so this clears the later of the two with margin. The other provider
-- updates around 00:30 UTC and is a day-granular source anyway, so one run
-- catches both.
--
-- Scheduled only where pg_cron exists, so this still applies on a plain
-- Postgres used for self-hosting.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'opensplit-fetch-fx',
      '30 16 * * *',
      'select public.trigger_fx_fetch()'
    );
  end if;
end;
$$;
