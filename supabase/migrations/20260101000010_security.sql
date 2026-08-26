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
-- Column rules for members, as a trigger rather than a policy.
--
-- RLS decides which ROWS a statement may touch and stops there. It cannot say
-- "this column, but only on your own row", and WITH CHECK cannot see OLD at
-- all — so the policy above, on its own, admits any member of a group to
-- rewrite any other member of that group. That is too much:
--
--   * set role = 'owner' on yourself, and then delete the group;
--   * rewrite somebody else's upi_vpa, so the settle-up handoff pays you;
--   * null out somebody's profile_id, and they lose the group entirely.
--
-- All three were reachable. So the row scope stays in the policy and the
-- column rules live here, where OLD and NEW are both in hand and a refusal can
-- say what it refused — an RLS failure on UPDATE just matches zero rows and
-- reports nothing at all.
-- ----------------------------------------------------------------------------
create or replace function guard_member_update()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  -- Rows whose descriptive fields you may edit: your own, and any placeholder.
  -- Placeholders are deliberately open — somebody has to be able to name and
  -- pay a person who has never opened the app, which is the entire point of
  -- them existing.
  v_own_or_placeholder boolean :=
    old.profile_id is null or old.profile_id = auth.uid();
  v_owner boolean := is_group_owner(old.group_id);
begin
  if new.id is distinct from old.id
     or new.group_id is distinct from old.group_id
     or new.joined_at is distinct from old.joined_at then
    raise exception 'A member cannot be moved between groups or re-identified'
      using errcode = 'insufficient_privilege';
  end if;

  -- The invite claim, and nothing else. null -> yourself is redeem_invite
  -- doing its one job. Every other transition either hands your place to
  -- somebody else or takes somebody's away.
  if new.profile_id is distinct from old.profile_id
     and not (old.profile_id is null and new.profile_id = auth.uid()) then
    raise exception
      'A member''s account can only be claimed, never reassigned'
      using errcode = 'insufficient_privilege';
  end if;

  if new.role is distinct from old.role and not v_owner then
    raise exception 'Only an owner can change a role'
      using errcode = 'insufficient_privilege';
  end if;

  if (new.display_name is distinct from old.display_name
      or new.upi_vpa is distinct from old.upi_vpa)
     and not (v_own_or_placeholder or v_owner) then
    raise exception
      'Only % or an owner can change that name or payment handle',
      old.display_name
      using errcode = 'insufficient_privilege';
  end if;

  if new.left_at is distinct from old.left_at
     and not (v_own_or_placeholder or v_owner) then
    raise exception 'Only an owner can remove somebody else from a group'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- Fires before trg_members_touch, which is alphabetical and therefore luck;
-- it does not matter either way, since touching updated_at is not something
-- this guards.
create trigger trg_members_guard
  before update on members
  for each row execute function guard_member_update();

-- ----------------------------------------------------------------------------
-- Deleting a group.
--
-- entry_payers and entry_shares reference members with ON DELETE RESTRICT, so
-- the cascade from `groups` stops dead the moment a group has a single expense
-- in it. That is the correct outcome — financial rows are never destroyed —
-- but the message Postgres produces for it names a foreign key the caller has
-- never heard of.
--
-- The policy and the GRANT therefore describe a capability that only really
-- exists for an empty group, and this says so in those words.
-- ----------------------------------------------------------------------------
create or replace function guard_group_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Only people are stopped. auth.uid() is null exactly when there is no JWT,
  -- which is to say when this is the scheduled purge running as postgres —
  -- and that job has already checked far more than this trigger does: archived,
  -- a year silent, and every balance settled to zero. Refusing it here would
  -- mean the only groups the reaper could ever collect are the empty ones,
  -- which are not the ones taking up room.
  if auth.uid() is not null
     and exists (select 1 from entries where group_id = old.id) then
    raise exception
      'This group has expenses recorded in it, so it cannot be deleted. '
      'Archive it instead.'
      using errcode = 'dependent_objects_still_exist';
  end if;
  return old;
end;
$$;

create trigger trg_groups_guard_delete
  before delete on groups
  for each row execute function guard_group_delete();

-- ----------------------------------------------------------------------------
-- Categories: a fixed global list, readable by anyone signed in.
--
-- No write policy, deliberately. The list is seeded by migration and is the
-- same everywhere; a category only one device knows about would tag entries
-- that read as uncategorised for everybody else.
-- ----------------------------------------------------------------------------
create policy categories_read on categories
  for select to authenticated using (true);

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

-- ----------------------------------------------------------------------------
-- The activity log.
--
-- Readable by the group, writable by nobody at all.
--
-- There is deliberately no insert policy, which is what stops a client writing
-- its own history through PostgREST — and it is also why the log is not written
-- from inside upsert_entry, which runs as the caller and would be refused here
-- like anyone else. The single writer is record_entry_event, a SECURITY DEFINER
-- trigger on entries.
--
-- No update or delete policy either, and that is the point of an audit trail:
-- being able to quietly rewrite the record of an edit would defeat the entire
-- reason the record exists.
-- ----------------------------------------------------------------------------
create policy entry_events_read on entry_events
  for select to authenticated using (is_group_member(group_id));

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
