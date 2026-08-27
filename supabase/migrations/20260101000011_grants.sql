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
-- authenticated only, and that is not an oversight: the app signs in
-- anonymously before it does anything at all, so every request it makes carries
-- a session. Nothing is ever read by the `anon` role, and a grant for a caller
-- that does not exist is API surface to maintain for nobody.
grant select on currencies to authenticated;
grant select on categories to authenticated;
grant select on fx_rates   to authenticated;

-- ----------------------------------------------------------------------------
-- Group-scoped data.
-- ----------------------------------------------------------------------------
grant select, insert, update         on profiles to authenticated;
grant select, insert, update         on groups   to authenticated;
grant select, insert, update         on members  to authenticated;
grant select, insert, update         on entries  to authenticated;
grant select, insert, update, delete on invites    to authenticated;

-- upsert_entry replaces children wholesale, so the caller genuinely needs
-- DELETE on these two.
grant select, insert, update, delete on entry_payers to authenticated;
grant select, insert, update, delete on entry_shares to authenticated;

-- assert_balanced() keeps its default PUBLIC execute grant, and has to: the
-- three constraint triggers that enforce the balance invariant are SECURITY
-- INVOKER, so each of them calls it as whoever made the write. Revoking it
-- would make every entry write fail at COMMIT.
--
-- Harmless as API surface. It returns nothing, and it reads entries,
-- entry_payers and entry_shares as the caller — so an entry the caller cannot
-- see reads as absent and the function returns silently, exactly as it does
-- for one deleted in the same transaction.

-- The activity log: readable by the group, appended to in your own name.
--
-- SELECT and INSERT, and nothing else. The device that made a change is what
-- describes it — see entry_events_insert, which pins the actor to the caller's
-- own member row — so appending has to be reachable through PostgREST.
--
-- No UPDATE or DELETE anywhere, at either level, and that half is unchanged: an
-- audit trail somebody can quietly rewrite is not one. Two independent locks on
-- that door, since there is no policy for either verb.
grant select, insert on entry_events to authenticated;

-- Deliberately no DELETE on entries, members or groups. None of the three has
-- an RLS delete policy either; this is the second lock on the same door.
--
-- Groups joined that list when the owner role went. The capability was already
-- unreachable — nothing in the app has ever deleted a group, and a trigger
-- refused it for any group with an expense in it — so it was a policy, a grant
-- and a guard describing something nobody could do. Archiving is the operation
-- people actually want, and the scheduled purge is what eventually collects a
-- group that is archived, a year silent and settled to zero.

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

-- Reading an invite comes BEFORE having an account, so this is the one function
-- in the schema granted to anon. That is the whole point of it: somebody who
-- taps a friend's link has to be shown what they were invited to before being
-- asked who they are, and at that moment they have no session. It redeems
-- nothing and reveals only what the link already tells whoever is holding it.
grant execute on function peek_invite(uuid) to anon, authenticated;

grant execute on function request_fx_backfill(date, char(3)) to authenticated;

-- Registering a device, including taking a token over from whoever held it
-- before. See the note on the function: it can only ever write auth.uid().
grant execute on function register_device_token(text, text) to authenticated;

-- Helpers used inside policies.
grant execute on function is_group_member(uuid)  to authenticated;
grant execute on function is_group_creator(uuid) to authenticated;

-- fx_rate_as_of() and fx_convert() are deliberately callable by nobody. They
-- are the server's own statement of what the pivot table means, which pgTAP
-- checks the Dart conversion against — the same role v_member_balances plays
-- for the balance fold. Clients convert locally from the mirrored table and
-- have never called either; exposing them as RPCs promised an API that nothing
-- asked for.
revoke execute on function fx_rate_as_of(char(3), date) from public, anon, authenticated;
revoke execute on function fx_convert(char(3), char(3), date) from public, anon, authenticated;

-- Likewise: the fetcher asks what it already holds, and nobody else needs to.
revoke execute on function fx_currencies_covered(date)
  from public, anon, authenticated;

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
grant execute on function fx_currencies_covered(date) to service_role;

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

-- Dormancy, likewise. archive_dormant_groups touches one reversible column and
-- purge_settled_dormant_groups deletes groups outright; neither is anything a
-- client should be able to call, at any scale, for any reason.
revoke execute on function archive_dormant_groups(interval)
  from public, anon, authenticated;
revoke execute on function purge_settled_dormant_groups(interval)
  from public, anon, authenticated;

-- Deleting your own account, and nobody else's. It takes no arguments and
-- reads auth.uid() itself, which is what makes it safe to expose: there is no
-- parameter to point at somebody else.
grant execute on function delete_account() to authenticated;
