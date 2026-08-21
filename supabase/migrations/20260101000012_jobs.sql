-- ============================================================================
-- Scheduled work.
--
-- Both jobs are created only where pg_cron exists, so this still applies on a
-- plain Postgres used for self-hosting — which then simply has no scheduled
-- work, and can drive the same functions from any external scheduler.
--
-- unschedule-then-schedule so re-running this cannot leave two jobs racing.
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not installed; no jobs scheduled';
    return;
  end if;

  -- Exchange rates, daily.
  --
  -- ECB publishes around 16:00 CET, which is 14:00 or 15:00 UTC depending on
  -- the season, so this clears the later of the two with margin. The other
  -- provider updates around 00:30 UTC and is day-granular anyway, so one run
  -- catches both.
  perform cron.unschedule('opensplit-fetch-fx')
    where exists (select 1 from cron.job where jobname = 'opensplit-fetch-fx');

  perform cron.schedule(
    'opensplit-fetch-fx',
    '30 16 * * *',
    'select public.trigger_fx_fetch()'
  );

  -- Abandoned anonymous accounts, daily.
  --
  -- Anonymous sign-in is the default entry path, so it is also unauthenticated
  -- row creation, and anonymous users count toward MAU. Only genuinely empty
  -- ones are reaped; the function refuses anyone who belongs to a group.
  perform cron.unschedule('opensplit-cleanup-anon')
    where exists (select 1 from cron.job where jobname = 'opensplit-cleanup-anon');

  perform cron.schedule(
    'opensplit-cleanup-anon',
    '17 3 * * *',
    'select public.cleanup_abandoned_anonymous_users()'
  );
end;
$$;
