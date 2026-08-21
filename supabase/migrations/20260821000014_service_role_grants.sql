-- Grants for the Edge Functions.
--
-- service_role bypasses RLS but NOT table privileges, and this project grants
-- explicitly rather than relying on defaults. The failure mode is a confusing
-- one — "permission denied for table currencies" thrown from inside a function
-- that is supposedly all-powerful — so it is worth stating why each of these
-- exists.

-- fetch-fx reads the currency list to decide what to fetch, reads and updates
-- provider rows to run the waterfall and record its outcome, and writes rates.
grant select                 on currencies   to service_role;
grant select, insert, update on fx_rates     to service_role;
grant select, update         on fx_providers to service_role;

-- notify-entry deletes registrations that FCM has reported as dead. Without
-- this the send succeeds, the cleanup fails, and stale tokens accumulate
-- forever while every fan-out retries them — visible only in function logs.
grant select, delete on device_tokens to service_role;

-- Both functions reach the tables above through PostgREST, which needs schema
-- usage before any of it applies.
grant usage on schema public to service_role;
