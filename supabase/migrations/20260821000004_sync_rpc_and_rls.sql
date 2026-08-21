-- ============================================================================
-- Make the write path support cursor sync, and close two RLS gaps.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- upsert_entry, second cut.
--
-- Three changes, each forced by the sync design:
--
--  1. It returns the whole row, not just an id. The client has to adopt the
--     server's `updated_at` immediately, or the very next delta pull sees its
--     own write as a remote change and reapplies it.
--
--  2. It upserts on the primary key. Ids are generated on the device — they
--     have to be, since an expense is created and shown long before it is
--     synced — so the id is the identity. `client_key` stays as the guard
--     against a retry creating a duplicate.
--
--  3. The conflict branch updates every field and stamps `updated_at`. The
--     first version only touched `description`, so a retried write with edited
--     content would be silently discarded and the row would never surface in
--     any later delta.
--
-- `created_by` and `created_at` are preserved on update: an edit is a revision
-- of the same fact, not a new one.
-- ---------------------------------------------------------------------------
create or replace function upsert_entry(
  p_id          uuid,
  p_group_id    uuid,
  p_currency    char(3),
  p_amount      bigint,
  p_payers      jsonb,
  p_shares      jsonb,
  p_description text        default '',
  p_kind        entry_kind  default 'expense',
  p_split_kind  split_kind  default 'equal',
  p_entry_date  date        default current_date,
  p_category_id uuid        default null,
  p_notes       text        default null,
  p_fx_rate     numeric     default null,
  p_fx_source   text        default null,
  p_client_key  uuid        default null,
  p_algo_version smallint   default 1
)
returns entries
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_member uuid;
  v_row    entries;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of group %', p_group_id
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_member
    from members
   where group_id = p_group_id and profile_id = auth.uid() and left_at is null;

  insert into entries (
    id, group_id, kind, description, category_id, currency, amount_minor,
    entry_date, split_kind, fx_rate, fx_source, fx_at, notes,
    created_by, client_key, algo_version, updated_at
  ) values (
    p_id, p_group_id, p_kind, p_description, p_category_id, p_currency,
    p_amount, p_entry_date, p_split_kind, p_fx_rate, p_fx_source,
    case when p_fx_rate is not null then now() end, p_notes,
    v_member, p_client_key, p_algo_version, now()
  )
  on conflict (id) do update set
    kind         = excluded.kind,
    description  = excluded.description,
    category_id  = excluded.category_id,
    currency     = excluded.currency,
    amount_minor = excluded.amount_minor,
    entry_date   = excluded.entry_date,
    split_kind   = excluded.split_kind,
    fx_rate      = excluded.fx_rate,
    fx_source    = excluded.fx_source,
    fx_at        = excluded.fx_at,
    notes        = excluded.notes,
    algo_version = excluded.algo_version,
    -- Server time, never the client's. Two devices with skewed clocks must not
    -- be able to decide a conflict between themselves.
    updated_at   = now()
  returning * into v_row;

  -- Replaced wholesale rather than diffed, matching what the client does, so
  -- the two cannot disagree about what an edit means. The deferred constraint
  -- trigger checks the result at COMMIT.
  delete from entry_payers where entry_id = v_row.id;
  delete from entry_shares where entry_id = v_row.id;

  insert into entry_payers (entry_id, member_id, amount_minor)
  select v_row.id,
         (x->>'member_id')::uuid,
         (x->>'amount_minor')::bigint
    from jsonb_array_elements(p_payers) x;

  insert into entry_shares (entry_id, member_id, amount_minor, weight)
  select v_row.id,
         (x->>'member_id')::uuid,
         (x->>'amount_minor')::bigint,
         (x->>'weight')::numeric
    from jsonb_array_elements(p_shares) x;

  return v_row;
end;
$$;

-- The single-argument signature from 0001 is gone; drop it so a stale client
-- gets a clear "function does not exist" rather than silently writing rows
-- that never appear in a delta.
drop function if exists upsert_entry(
  uuid, char(3), bigint, jsonb, jsonb, text, entry_kind, split_kind,
  date, uuid, text, numeric, text, uuid, uuid
);

-- ---------------------------------------------------------------------------
-- delete_entry returns the row, for the same reason upsert_entry does.
-- ---------------------------------------------------------------------------
create or replace function delete_entry(p_entry_id uuid)
returns entries
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_row entries;
begin
  update entries set deleted_at = now(), updated_at = now()
   where id = p_entry_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'No such entry %', p_entry_id
      using errcode = 'no_data_found';
  end if;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS gap 1: entries could be hard-deleted.
--
-- 0001 grants `for all`, which includes DELETE, while the whole design says
-- financial rows are never physically removed — a hard delete also vanishes
-- from the delta feed, so other devices keep the row forever with no way to
-- learn it went. Replaced with explicit per-command policies.
-- ---------------------------------------------------------------------------
drop policy entries_write on entries;

create policy entries_insert on entries
  for insert to authenticated with check (is_group_member(group_id));

create policy entries_update on entries
  for update to authenticated
  using (is_group_member(group_id))
  with check (is_group_member(group_id));

-- Deliberately no delete policy: RLS denies by default, so DELETE on entries
-- is impossible for everyone. Use delete_entry, which soft-deletes.

-- ---------------------------------------------------------------------------
-- RLS gap 2: destructive group actions were open to anonymous users.
--
-- An anonymous session is one device with no recovery. It may record expenses
-- freely, but it must not be able to destroy a group other people are relying
-- on — the account cannot be recovered to undo it.
-- ---------------------------------------------------------------------------
create policy groups_delete on groups for delete to authenticated
  using (
    is_group_owner(id)
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
  );

-- Cursor sync reads members and groups in full on every pull, so they need to
-- stay cheap to scan as groups accumulate.
create index if not exists idx_members_group_active
  on members (group_id) where left_at is null;
