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

  -- Dormant groups, daily.
  --
  -- Archiving is reversible and touches one column, so it runs unattended
  -- without ceremony. The purge is the opposite and is scheduled weekly rather
  -- than daily to make that difference visible in the schedule itself: it can
  -- only ever remove a group that is archived, a year silent, and settled to
  -- zero, so there is nothing for a daily run to catch that a weekly one
  -- misses.
  perform cron.unschedule('opensplit-archive-dormant')
    where exists (select 1 from cron.job where jobname = 'opensplit-archive-dormant');

  perform cron.schedule(
    'opensplit-archive-dormant',
    '41 3 * * *',
    'select public.archive_dormant_groups()'
  );

  perform cron.unschedule('opensplit-purge-settled')
    where exists (select 1 from cron.job where jobname = 'opensplit-purge-settled');

  perform cron.schedule(
    'opensplit-purge-settled',
    '13 4 * * 0',
    'select public.purge_settled_dormant_groups()'
  );
end;
$$;
