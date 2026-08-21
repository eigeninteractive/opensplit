-- Actually enable the scheduling machinery.
--
-- The earlier migration scheduled the daily fetch only `if exists (... pg_cron)`
-- so that it would still apply on a plain Postgres. On a fresh Supabase project
-- neither extension is installed yet, so that condition was false and the job
-- was silently never created — the guard intended to make the migration
-- portable had quietly made the feature inert.
--
-- Enable them here, tolerantly: a self-hosted Postgres without these extensions
-- still applies this file, and simply has no scheduled fetch. Rates can then be
-- driven by any external scheduler hitting the function directly.
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net unavailable (%); scheduled fetch disabled', sqlerrm;
end;
$$;

do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron unavailable (%); scheduled fetch disabled', sqlerrm;
end;
$$;

-- Now that pg_cron may exist, schedule for real. unschedule-then-schedule so
-- this is idempotent and so re-running it cannot leave two jobs racing.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('opensplit-fetch-fx')
      where exists (select 1 from cron.job where jobname = 'opensplit-fetch-fx');

    perform cron.schedule(
      'opensplit-fetch-fx',
      '30 16 * * *',
      'select public.trigger_fx_fetch()'
    );
  end if;
end;
$$;
