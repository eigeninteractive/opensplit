-- Exchange rates must be positive.
--
-- fx_rate is a display-only snapshot: it never folds into a balance, so a bad
-- value cannot move money between people. It can still make another member's
-- converted summary absurd, and there is no legitimate write that needs a rate
-- of zero or below, so the column should simply refuse them.
--
-- Written as a constraint rather than a check in the RPC because entries are
-- also written by direct PostgREST upserts and by future code paths that do not
-- exist yet. The table is the only place that sees all of them.
alter table entries
  add constraint entries_fx_rate_positive
  check (fx_rate is null or fx_rate > 0);

-- Provenance without a rate is meaningless, and a rate whose source is unknown
-- cannot be audited later. They travel together or not at all.
alter table entries
  add constraint entries_fx_complete
  check (num_nulls(fx_rate, fx_source, fx_at) in (0, 3));
