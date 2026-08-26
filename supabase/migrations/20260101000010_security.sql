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

-- Any member may rename a group, archive it, or turn debt simplification on
-- and off. None of it touches money, all of it is reversible by anybody who
-- disagrees, and all of it is visible — which is the test for whether
-- something needs a rank behind it.
create policy groups_update on groups
  for update to authenticated
  using (is_group_member(id) or created_by = auth.uid())
  with check (is_group_member(id) or created_by = auth.uid());

-- There is deliberately no delete policy, and no DELETE grant to match — see
-- the note in the grants file. A group is archived, never destroyed, and the
-- only paths that remove one are the scheduled purge and delete_account(),
-- both of which run as the definer and both of which check far more first.

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
--   * rewrite somebody else's upi_vpa, so the settle-up handoff pays you;
--   * null out somebody's profile_id, and they lose the group entirely;
--   * set left_at on somebody else, cutting them out of the group.
--
-- All three were reachable. So the row scope stays in the policy and the
-- column rules live here, where OLD and NEW are both in hand and a refusal can
-- say what it refused — an RLS failure on UPDATE just matches zero rows and
-- reports nothing at all.
--
-- These rules used to carry an exemption for a group owner. They no longer do,
-- and the first of the three is why: an owner could rewrite another member's
-- payment handle, which is the one power in this schema that can redirect real
-- money. Nobody needs it, so nobody has it.
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
  --
  -- With one exception, and it is not a loophole: the cascade from a deleted
  -- profile. `members.profile_id` is ON DELETE SET NULL, which is what turns a
  -- membership back into a placeholder when its account is deleted — see
  -- delete_account(). That arrives here as claimed -> null and is otherwise
  -- indistinguishable from somebody trying to unclaim a member out from under
  -- them, so it is told apart by the one thing only the real case can be true
  -- of: the account is already gone.
  if new.profile_id is distinct from old.profile_id
     and not (old.profile_id is null and new.profile_id = auth.uid())
     and not (
       new.profile_id is null
       and not exists (select 1 from profiles where id = old.profile_id)
     ) then
    raise exception
      'A member''s account can only be claimed, never reassigned'
      using errcode = 'insufficient_privilege';
  end if;

  -- Your own name and handle, or a placeholder's. A placeholder's are shared
  -- bookkeeping — somebody has to be able to name and pay a person who has
  -- never opened the app — but a claimed member's belong to that person, and
  -- their profile is what the app displays for them anyway.
  if (new.display_name is distinct from old.display_name
      or new.upi_vpa is distinct from old.upi_vpa)
     and not v_own_or_placeholder then
    raise exception
      'Only % can change their own name or payment handle', old.display_name
      using errcode = 'insufficient_privilege';
  end if;

  -- Leaving is always yours to do, settled or not: a debt is not a reason
  -- somebody can be held in a group, and the app says plainly that leaving
  -- does not clear one.
  --
  -- Removing somebody else is different, because it is not only a removal.
  -- `is_group_member` requires `left_at is null`, so it also cuts them off from
  -- reading the group — and the person most worth cutting off is exactly the
  -- one still owed money, or the one still chasing you for it. Requiring a zero
  -- balance in every currency is what makes removal a piece of tidying up
  -- rather than a way to walk away from a debt or to hide from one.
  --
  -- v_member_balances lists only non-zero positions, so "no rows" is the
  -- definition of settled — the same one purge_settled_dormant_groups uses.
  if new.left_at is distinct from old.left_at
     and old.profile_id is distinct from auth.uid()
     and exists (
       select 1 from v_member_balances b
        where b.group_id = old.group_id and b.member_id = old.id
     ) then
    raise exception
      '% is not settled up in this group, so they cannot be removed from it',
      old.display_name
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
