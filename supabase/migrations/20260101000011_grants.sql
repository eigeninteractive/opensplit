-- ============================================================================
-- Privileges.
--
-- RLS decides WHICH ROWS a role may touch; it says nothing about whether the
-- role may touch the table at all. Both are required, and a missing GRANT fails
-- as "permission denied for table ..." from inside a SECURITY INVOKER function
-- — which reads like an RLS problem and is not.
--
-- Spelled out rather than left to a hosting provider's defaults, so a
-- self-hosted plain Postgres behaves identically. Every table above has RLS
-- enabled, so these grants widen nothing on their own; they only let the
-- policies be consulted.
-- ============================================================================

grant usage on schema public to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Reference data.
-- ----------------------------------------------------------------------------
grant select on currencies to anon, authenticated;
grant select on categories to anon, authenticated;
grant select on fx_rates   to anon, authenticated;

-- ----------------------------------------------------------------------------
-- Group-scoped data.
-- ----------------------------------------------------------------------------
grant select, insert, update         on profiles to authenticated;
grant select, insert, update, delete on groups   to authenticated;
grant select, insert, update         on members  to authenticated;
grant select, insert, update         on entries  to authenticated;
grant select, insert, update, delete on categories to authenticated;
grant select, insert, update, delete on invites    to authenticated;

-- upsert_entry replaces children wholesale, so the caller genuinely needs
-- DELETE on these two.
grant select, insert, update, delete on entry_payers to authenticated;
grant select, insert, update, delete on entry_shares to authenticated;

-- Deliberately no DELETE on entries or members. Neither has an RLS delete
-- policy either; this is the second lock on the same door.

grant select on v_member_balances to authenticated;

grant select, insert, update, delete on device_tokens to authenticated;

-- ----------------------------------------------------------------------------
-- Functions callable by users.
-- ----------------------------------------------------------------------------
grant execute on function upsert_entry(
  uuid, uuid, char(3), bigint, jsonb, jsonb, text, entry_kind, split_kind,
  date, uuid, text, numeric, text, uuid
) to authenticated;
grant execute on function delete_entry(uuid) to authenticated;
grant execute on function create_invite(uuid, interval) to authenticated;

-- Anyone holding a token may attempt redemption; the function does the rest.
grant execute on function redeem_invite(uuid) to authenticated;

grant execute on function request_fx_backfill(date, char(3)) to authenticated;
grant execute on function fx_rate_as_of(char(3), date) to anon, authenticated;
grant execute on function fx_convert(char(3), char(3), date) to anon, authenticated;

-- Helpers used inside policies.
grant execute on function is_group_member(uuid)  to anon, authenticated;
grant execute on function is_group_owner(uuid)   to anon, authenticated;
grant execute on function is_group_creator(uuid) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- The Edge Functions.
--
-- service_role bypasses RLS but NOT table privileges. Without these the
-- functions fail with a confusing "permission denied" thrown from inside code
-- that is supposedly all-powerful.
-- ----------------------------------------------------------------------------

-- fetch-fx reads the currency list to decide what to fetch, reads and updates
-- provider rows to run the waterfall and record its outcome, and writes rates.
grant select                 on currencies   to service_role;
grant select, insert, update on fx_rates     to service_role;
grant select, update         on fx_providers to service_role;

-- notify-entry deletes registrations FCM has reported as dead. Without this the
-- send succeeds, the cleanup fails, and stale tokens accumulate forever while
-- every fan-out retries them — visible only in function logs.
grant select, delete on device_tokens to service_role;

-- tokens_for_entry deliberately reads other people's tokens, which no
-- user-facing policy allows. It is therefore service-role only.
revoke execute on function tokens_for_entry(uuid) from public, anon, authenticated;
grant  execute on function tokens_for_entry(uuid) to service_role;

-- Operator-only: these drive outbound requests and delete accounts.
revoke execute on function trigger_fx_fetch(jsonb) from public, anon, authenticated;
revoke execute on function cleanup_abandoned_anonymous_users() from public, anon, authenticated;
