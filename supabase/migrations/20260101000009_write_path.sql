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
--
-- THE ONLY DOOR.
--
-- Both are SECURITY DEFINER, and `authenticated` has no INSERT, UPDATE or
-- DELETE on entries, entry_payers or entry_shares. Every write to the ledger
-- comes through here or does not happen.
--
-- That is a change of kind, not degree. While direct DML was reachable, any
-- guarantee these functions offered was advisory -- a client could simply issue
-- the UPDATE itself and meet none of them. Closing the second door is what
-- makes "the server records every change" a fact about the schema rather than a
-- description of the happy path.
--
-- SECURITY DEFINER means RLS no longer runs underneath these bodies, so what
-- RLS used to catch has to be stated here instead. Both functions therefore
-- open by establishing that the caller may touch what they have named, and
-- neither takes an actor as a parameter -- authorship is read from auth.uid(),
-- so there is nothing to point at somebody else.
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
  p_client_key  uuid        default null,

  -- The server version this edit was composed against.
  --
  -- Null means "I am not claiming a base": a row this device invented, or a
  -- client that does not send one. Both skip the check below, which is why
  -- adding this parameter changed no existing behaviour.
  p_base_updated_at timestamptz default null
)
returns entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member   uuid;
  v_row      entries;
  v_current  timestamptz;
  v_stored   jsonb;
  v_incoming jsonb;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of group %', p_group_id
      using errcode = 'insufficient_privilege';
  end if;

  -- An id that already belongs to a DIFFERENT group.
  --
  -- Under SECURITY INVOKER this was caught for free: the UPDATE half of the
  -- upsert matched no rows the caller could see, and RLS refused it. There is
  -- no RLS underneath any more, and ON CONFLICT deliberately does not rewrite
  -- group_id -- so without this line a member of one group could name an
  -- expense in a group they have never been in and rewrite its amount, its
  -- description and every share on it, in place.
  if exists (
    select 1 from entries where id = p_id and group_id <> p_group_id
  ) then
    raise exception 'Entry % belongs to another group', p_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The expense moved since this edit was composed.
  --
  -- Whole-entry last-write-wins is the rule everywhere else here, and it is the
  -- right rule for an expense: amount, payers and shares are one coherent fact,
  -- not a bag of independent columns that can be merged pairwise. Merging them
  -- is how you get a row that balances arithmetically and describes something
  -- nobody asked for.
  --
  -- What last-write-wins cannot do on its own is tell anybody it happened. Two
  -- people edit one expense, the second push overwrites the first, and the
  -- person whose edit vanished is never told -- while the feed reads as though
  -- they reverted their friend on purpose.
  --
  -- The predicate is deliberately about money and not about staleness. A stale
  -- base alone is not a conflict worth refusing: two people fixing a typo
  -- should not have to arbitrate, and last-write-wins on prose costs nothing.
  -- What cannot pass silently is a write that would move money away from where
  -- the server currently has it -- and because this RPC writes the whole row,
  -- that includes an edit which changes only the description while carrying a
  -- stale amount along with it. Comparing the money rather than the parameters
  -- catches exactly that case and lets the harmless ones through.
  if p_base_updated_at is not null then
    select updated_at into v_current from entries where id = p_id;

    if found and v_current is distinct from p_base_updated_at then
      select jsonb_build_object(
               'amount', e.amount_minor,
               'payers', coalesce((
                 select jsonb_agg(
                          jsonb_build_object(
                            'member', p.member_id, 'amount', p.amount_minor)
                          order by p.member_id)
                   from entry_payers p where p.entry_id = e.id), '[]'::jsonb),
               'shares', coalesce((
                 select jsonb_agg(
                          jsonb_build_object(
                            'member', s.member_id, 'amount', s.amount_minor)
                          order by s.member_id)
                   from entry_shares s where s.entry_id = e.id), '[]'::jsonb))
        into v_stored
        from entries e where e.id = p_id;

      -- The same shape from the parameters, so the comparison is between two
      -- canonical forms rather than between a row and a payload. Ordered by
      -- member, and weights left out on purpose: a weight is how a split was
      -- expressed, the amounts are what anybody owes.
      select jsonb_build_object(
               'amount', p_amount,
               'payers', coalesce((
                 select jsonb_agg(
                          jsonb_build_object(
                            'member', (x->>'member_id')::uuid,
                            'amount', (x->>'amount_minor')::bigint)
                          order by (x->>'member_id')::uuid)
                   from jsonb_array_elements(p_payers) x), '[]'::jsonb),
               'shares', coalesce((
                 select jsonb_agg(
                          jsonb_build_object(
                            'member', (x->>'member_id')::uuid,
                            'amount', (x->>'amount_minor')::bigint)
                          order by (x->>'member_id')::uuid)
                   from jsonb_array_elements(p_shares) x), '[]'::jsonb))
        into v_incoming;

      if v_stored is distinct from v_incoming then
        -- serialization_failure, which is what this is: a write composed
        -- against a version that no longer exists. Nothing in this stack
        -- retries the code automatically, and the client maps it to its own
        -- third outcome -- neither a backoff nor a dead letter.
        raise exception
          'Entry % changed since this edit was composed', p_id
          using errcode = '40001';
      end if;
    end if;
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
    -- be able to decide a conflict between themselves. Restated by
    -- trg_entries_touch either way, which is what makes it true of every write
    -- rather than only of this one.
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
create or replace function delete_entry(
  p_entry_id uuid,
  p_base_updated_at timestamptz
)
returns entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row entries;
begin
  -- `is_group_member` in the WHERE, and it is doing real work.
  --
  -- This function used to carry no membership test at all. It did not need
  -- one: as SECURITY INVOKER the UPDATE was filtered by the entries_update
  -- policy, so naming somebody else's expense matched zero rows and fell
  -- through to the "no such entry" below. Made SECURITY DEFINER with that
  -- accident left in place, it would have deleted any expense in the database
  -- from its id alone.
  select * into v_row
    from entries
   where id = p_entry_id
     and is_group_member(group_id);

  -- Deliberately the same message whether the expense does not exist or simply
  -- is not the caller's to touch. Distinguishing them would answer "does this
  -- id exist?" for anybody willing to ask.
  if v_row.id is null then
    raise exception 'No such entry %', p_entry_id
      using errcode = 'no_data_found';
  end if;

  -- A retry after the server committed but before its response reached the
  -- device is idempotent. The row is already in the requested state, so return
  -- its authoritative version even though the caller still carries the older
  -- base.
  if v_row.deleted_at is not null then
    return v_row;
  end if;

  -- Unlike a prose-only edit, deleting always moves money: every payer and
  -- share disappears from the live balance. It must therefore be composed
  -- against the exact server version the device last observed.
  if p_base_updated_at is null
     or v_row.updated_at is distinct from p_base_updated_at then
    raise exception
      'Entry % changed since this deletion was composed', p_entry_id
      using errcode = '40001';
  end if;

  update entries
     set deleted_at = now()
   where id = p_entry_id
  returning * into v_row;

  return v_row;
end;
$$;
