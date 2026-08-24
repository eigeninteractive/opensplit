-- ============================================================================
-- Row-level security.
--
-- Every policy in one place, because "who can see what" is a single question
-- and answering it should not mean reading eight files.
--
-- Two rules run through all of it:
--
--   * Financial rows are never destroyed. There is no delete policy on entries
--     or members, so DELETE is impossible for everyone — a hard delete would
--     vanish from the delta feed and strand the row on every device that had
--     already synced it. Soft deletion is delete_entry and members.left_at.
--
--   * An upsert needs a SELECT policy. PostgREST pushes with INSERT ... ON
--     CONFLICT DO UPDATE so a retry after a dropped connection is idempotent,
--     and Postgres requires a SELECT policy admitting the proposed row for such
--     a statement. When it is missing the error reads "new row violates
--     row-level security policy", which names the INSERT policy and is nothing
--     to do with it — a plain INSERT of the identical row succeeds.
-- ============================================================================

-- Reference data. The app cannot render an amount without the exponent, so this
-- has to be readable by anyone who has got as far as a session.
create policy currencies_read on currencies
  for select to authenticated using (true);

-- Rates are public reference data too. There is deliberately no write policy:
-- only the service role, and therefore only the fetch-fx function, can publish
-- a rate.
create policy fx_rates_read on fx_rates
  for select to authenticated using (true);

-- ----------------------------------------------------------------------------
-- Profiles: yourself, plus anyone you share a group with.
-- ----------------------------------------------------------------------------
create policy profiles_read on profiles
  for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
        from members m1
        join members m2 on m2.group_id = m1.group_id
       where m1.profile_id = auth.uid()
         and m2.profile_id = profiles.id
    )
  );

create policy profiles_update on profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ----------------------------------------------------------------------------
-- Groups.
--
-- Read and update compare created_by directly rather than calling
-- is_group_creator(), because the helper reads the groups row this very
-- statement may still be inserting — it is false at check time. groups_insert
-- pins created_by to auth.uid(), so the comparison can only ever match the
-- genuine creator.
-- ----------------------------------------------------------------------------
create policy groups_read on groups
  for select to authenticated
  using (is_group_member(id) or created_by = auth.uid());

create policy groups_insert on groups
  for insert to authenticated with check (created_by = auth.uid());

create policy groups_update on groups
  for update to authenticated
  using (is_group_owner(id) or created_by = auth.uid())
  with check (is_group_owner(id) or created_by = auth.uid());

-- An anonymous session is one device with no recovery path. It may record
-- expenses freely, but it must not be able to destroy a group other people are
-- relying on, because the account cannot be recovered to undo it.
create policy groups_delete on groups
  for delete to authenticated
  using (
    is_group_owner(id)
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
  );

-- ----------------------------------------------------------------------------
-- Members.
--
-- THE BOOTSTRAP: gating every write behind is_group_member() is unsatisfiable
-- for the first member, because you become a member by inserting the row the
-- policy is refusing. Creating a group would succeed and then immediately fail,
-- leaving an empty group nobody could ever join. is_group_creator() is what
-- admits the creator's own first row.
-- ----------------------------------------------------------------------------
create policy members_read on members
  for select to authenticated
  using (is_group_member(group_id) or is_group_creator(group_id));

create policy members_insert on members
  for insert to authenticated
  with check (is_group_member(group_id) or is_group_creator(group_id));

create policy members_update on members
  for update to authenticated
  using (is_group_member(group_id) or is_group_creator(group_id))
  with check (is_group_member(group_id) or is_group_creator(group_id));

-- ----------------------------------------------------------------------------
-- Categories: global presets plus your own groups'.
-- ----------------------------------------------------------------------------
create policy categories_read on categories
  for select to authenticated
  using (group_id is null or is_group_member(group_id));

create policy categories_write on categories
  for all to authenticated
  using (group_id is not null and is_group_member(group_id))
  with check (group_id is not null and is_group_member(group_id));

-- ----------------------------------------------------------------------------
-- Entries, payers and shares.
-- ----------------------------------------------------------------------------
create policy entries_read on entries
  for select to authenticated using (is_group_member(group_id));

create policy entries_insert on entries
  for insert to authenticated with check (is_group_member(group_id));

create policy entries_update on entries
  for update to authenticated
  using (is_group_member(group_id))
  with check (is_group_member(group_id));

-- Payers and shares inherit access from the parent entry.
create policy entry_payers_all on entry_payers
  for all to authenticated
  using (exists (
    select 1 from entries e
     where e.id = entry_payers.entry_id and is_group_member(e.group_id)))
  with check (exists (
    select 1 from entries e
     where e.id = entry_payers.entry_id and is_group_member(e.group_id)));

create policy entry_shares_all on entry_shares
  for all to authenticated
  using (exists (
    select 1 from entries e
     where e.id = entry_shares.entry_id and is_group_member(e.group_id)))
  with check (exists (
    select 1 from entries e
     where e.id = entry_shares.entry_id and is_group_member(e.group_id)));

-- ----------------------------------------------------------------------------
-- Invites.
--
-- Members of a group can see and issue its invites. Note there is no policy
-- allowing a stranger to SELECT an invite: redemption goes through a
-- security-definer function, so possession of the token is the only proof
-- needed and the table itself stays closed.
-- ----------------------------------------------------------------------------
create policy invites_read on invites
  for select to authenticated using (is_group_member(group_id));

create policy invites_insert on invites
  for insert to authenticated with check (
    is_group_member(group_id) and created_by = auth.uid()
  );

create policy invites_delete on invites
  for delete to authenticated using (is_group_member(group_id));

-- ----------------------------------------------------------------------------
-- Device tokens: strictly your own.
--
-- A token is a capability to interrupt someone's phone. It must never be
-- readable by anyone else, including people in your groups.
-- ----------------------------------------------------------------------------
create policy device_tokens_own on device_tokens
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- fx_providers, fx_backfill_requests and app_settings deliberately have RLS
-- enabled and no policy at all: they are operator configuration and internal
-- bookkeeping, reachable only by the service role.
