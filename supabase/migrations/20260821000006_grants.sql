-- ============================================================================
-- Explicit privileges for the API roles.
--
-- Row-level security decides *which rows* a role may touch; it does nothing
-- about whether the role may touch the table at all. Both are required, and
-- missing GRANTs fail as "permission denied for table ..." from inside a
-- SECURITY INVOKER function, which reads like an RLS problem and is not.
--
-- Spelled out rather than left to a hosting provider's default privileges, so
-- that a self-hosted plain Postgres behaves identically. That is the whole
-- point of the self-hosting promise being first-class.
-- ============================================================================

grant usage on schema public to anon, authenticated;

-- Reference data: readable by anyone who has got as far as an anonymous
-- session, since the app cannot render an amount without the exponent.
grant select on currencies to anon, authenticated;
grant select on categories to anon, authenticated;

-- Group-scoped data. Every one of these tables has RLS enabled, so these
-- grants widen nothing on their own — they only let the policies be consulted.
grant select, insert, update on profiles      to authenticated;
grant select, insert, update, delete on groups to authenticated;
grant select, insert, update, delete on members to authenticated;
grant select, insert, update on entries        to authenticated;
grant select, insert, update, delete on categories to authenticated;
grant select, insert, update, delete on invites to authenticated;

-- upsert_entry replaces children wholesale, so the caller genuinely needs
-- DELETE on these two.
grant select, insert, update, delete on entry_payers to authenticated;
grant select, insert, update, delete on entry_shares to authenticated;

-- Deliberately no DELETE on entries. There is no RLS delete policy either;
-- this is the second lock on the same door. A hard delete would disappear from
-- the delta feed and strand the row on every device that already synced it.

grant select on v_member_balances to authenticated;

-- The write path.
grant execute on function upsert_entry(
  uuid, uuid, char(3), bigint, jsonb, jsonb, text, entry_kind, split_kind,
  date, uuid, text, numeric, text, uuid, smallint
) to authenticated;
grant execute on function delete_entry(uuid) to authenticated;
grant execute on function create_invite(uuid, interval) to authenticated;

-- Helpers used inside policies.
grant execute on function is_group_member(uuid) to anon, authenticated;
grant execute on function is_group_owner(uuid)  to anon, authenticated;
