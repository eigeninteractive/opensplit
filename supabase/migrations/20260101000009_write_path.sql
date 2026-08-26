-- ============================================================================
-- The write path: one RPC, one transaction.
--
-- The client never writes an entry and its payers and shares in three separate
-- calls. That would leave torn state on a dropped connection and defeat the
-- deferred trigger's purpose, which is to check the finished result at COMMIT.
--
-- payers / shares are jsonb arrays:
--   [{"member_id":"...","amount_minor":1200}]
--   [{"member_id":"...","amount_minor":400,"weight":1}]
--
-- Both functions return the stored row so the client can adopt the server's
-- updated_at. Without it the device keeps a local clock in the column that
-- decides conflicts, and last-write-wins ends up comparing a phone against a
-- server instead of two server timestamps.
-- ============================================================================

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
  p_client_key  uuid        default null
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

  -- A group somebody is still using is not dormant, whatever the reaper
  -- decided three months ago. Archiving is reversible precisely so that being
  -- wrong about it costs nothing, and this is the line that makes it so:
  -- adding an expense brings the group back to the list by itself, with
  -- nothing for the user to find or undo.
  update groups set archived_at = null, updated_at = now()
   where id = p_group_id and archived_at is not null;

  -- Authorship is the caller's own member row. There is deliberately no
  -- parameter for it: a client cannot attribute an expense to someone else.
  select id into v_member
    from members
   where group_id = p_group_id and profile_id = auth.uid() and left_at is null;

  insert into entries (
    id, group_id, kind, description, category_id, currency, amount_minor,
    entry_date, split_kind, fx_rate, fx_source, fx_at, notes,
    created_by, client_key, updated_at
  ) values (
    p_id, p_group_id, p_kind, p_description, p_category_id, p_currency,
    p_amount, p_entry_date, p_split_kind, p_fx_rate, p_fx_source,
    case when p_fx_rate is not null then now() end, p_notes,
    v_member, p_client_key, now()
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

-- Soft delete only. A hard delete would vanish from the delta feed, leaving the
-- row on every device that already synced it with no way to learn it went.
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
