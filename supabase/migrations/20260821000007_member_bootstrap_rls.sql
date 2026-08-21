-- ============================================================================
-- Fix: a group's creator could neither add themselves to it nor push it.
--
-- Two failures, both invisible until run against a real server.
--
-- 1. THE BOOTSTRAP DEADLOCK
--
--    0001 gates every write to `members` behind is_group_member(group_id).
--    That is unsatisfiable for the first member, because you become a member
--    by inserting the row the policy is refusing. Creating a group succeeded
--    and then immediately failed with "Not a member of group ...", leaving an
--    empty group nobody could ever join.
--
--    Checking groups.created_by inline does not work either: policy
--    expressions run as the calling role, so that subquery is itself filtered
--    by groups_read, which also demands membership. It has to go through a
--    SECURITY DEFINER helper, exactly as is_group_member does and for exactly
--    the same reason.
--
-- 2. ON CONFLICT NEEDS A *SELECT* POLICY
--
--    The client pushes with PostgREST upsert, because a retry after a dropped
--    connection has to be idempotent. That issues INSERT ... ON CONFLICT DO
--    UPDATE, and Postgres requires a SELECT policy admitting the proposed row
--    for such a statement — it has to be able to read back the row it may have
--    to update, and it establishes that up front rather than only on conflict.
--
--    The failure is reported as:
--        new row violates row-level security policy for table "groups"
--    which names the INSERT policy and is nothing to do with it. A plain
--    INSERT of the identical row succeeds; only the upsert fails. Widening the
--    UPDATE policy does not help either — it is the SELECT policy that has to
--    admit the row.
--
--    And the SELECT policy cannot use is_group_creator() here, because that
--    reads the groups row this very statement is still inserting, so it is
--    false at check time. It has to compare the proposed row's own created_by
--    column. groups_insert pins created_by to auth.uid(), so this can only
--    ever match the genuine creator.
-- ============================================================================

create or replace function is_group_creator(gid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from groups where id = gid and created_by = auth.uid()
  );
$$;

comment on function is_group_creator is
  'Bypasses RLS on its internal read so it can be used inside a policy without '
  'recursing. Only meaningful once the groups row exists — a policy on groups '
  'itself must compare created_by directly instead.';

grant execute on function is_group_creator(uuid) to anon, authenticated;

-- Direct column comparison, so it holds for a row that is still being
-- inserted. This is what lets the creator upsert their own group, and what
-- lets them see it in the window before they appear in it as a member.
drop policy groups_read on groups;
create policy groups_read on groups
  for select to authenticated
  using (is_group_member(id) or created_by = auth.uid());

drop policy groups_update on groups;
create policy groups_update on groups
  for update to authenticated
  using (is_group_owner(id) or created_by = auth.uid())
  with check (is_group_owner(id) or created_by = auth.uid());

-- Members are pushed after their group, so by the time these are evaluated the
-- groups row exists and the helper is meaningful.
drop policy members_read on members;
create policy members_read on members
  for select to authenticated
  using (is_group_member(group_id) or is_group_creator(group_id));

-- `for all` also granted DELETE, which contradicts members never being
-- removed. Replaced with explicit commands and no delete policy: a member who
-- has paid for anything must stay referenceable or their entries stop making
-- sense. Leaving is `left_at`.
drop policy members_write on members;

create policy members_insert on members
  for insert to authenticated
  with check (is_group_member(group_id) or is_group_creator(group_id));

create policy members_update on members
  for update to authenticated
  using (is_group_member(group_id) or is_group_creator(group_id))
  with check (is_group_member(group_id) or is_group_creator(group_id));
