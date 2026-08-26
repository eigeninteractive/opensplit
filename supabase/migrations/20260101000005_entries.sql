-- ============================================================================
-- The ledger.
--
-- Two shapes matter here.
--
-- entry_payers is a TABLE, not a paid_by column. Multiple payers on one bill is
-- ordinary ("I got the food, you got the drinks") and is where every simple
-- clone falls over.
--
-- entry_shares stores BOTH the resolved amount and the original weight. Storing
-- only the rule means a future rounding fix retroactively moves money that has
-- already been settled. Storing only the amount means the split cannot be
-- re-edited as "2:1:1". Store both.
-- ============================================================================

create table entries (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  kind          entry_kind not null default 'expense',
  description   text not null default '',
  category_id   uuid references categories(id) on delete set null,

  -- The currency the money was actually spent in. Never converted on write.
  currency      char(3) not null references currencies(code),
  amount_minor  bigint not null check (amount_minor > 0),

  entry_date    date not null default current_date,
  split_kind    split_kind not null default 'equal',

  -- Display-only snapshot of the rate to the group's default currency, as it
  -- stood on entry_date. Never re-fetched: what a rupee was worth on the night
  -- of the dinner is a fact about the transaction, not a live quote.
  --
  -- A rate of zero or below is meaningless and there is no legitimate write
  -- that needs one. Provenance without a rate cannot be audited, and a rate
  -- without provenance cannot be traced, so the three travel together.
  fx_rate       numeric(24,12),
  fx_source     text,
  fx_at         timestamptz,

  notes         text,

  -- A member id, not a profile id: authorship belongs to the group-scoped
  -- identity so a placeholder's expenses survive them claiming an account.
  created_by    uuid not null references members(id) on delete restrict,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,

  -- Client-generated, so a retried sync after a dropped connection is
  -- idempotent rather than creating a second expense.
  client_key    uuid,
  unique (group_id, client_key),

  constraint entries_fx_rate_positive
    check (fx_rate is null or fx_rate > 0),
  constraint entries_fx_complete
    check (num_nulls(fx_rate, fx_source, fx_at) in (0, 3))
);

-- The delta pull is:
--   select ... where group_id = ? and (updated_at, id) > cursor order by ...
--
-- `id` is the third column and not decoration: the cursor is the pair, because
-- `now()` is transaction time and a batch written together shares one
-- `updated_at`. Without `id` in the index the pull can seek on the timestamp
-- but has to sort the ties in memory, which is exactly the case a bulk sync
-- produces most of.
--
-- Deliberately NOT partial on `deleted_at is null`: a soft delete is itself a
-- delta the client must receive, otherwise a deleted expense lives forever on
-- every device that already synced it.
create index idx_entries_group_updated on entries (group_id, updated_at, id);

-- on delete restrict: a member with financial history can never be deleted.
-- Use members.left_at instead.
create table entry_payers (
  entry_id     uuid   not null references entries(id) on delete cascade,
  member_id    uuid   not null references members(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  primary key (entry_id, member_id)
);

create table entry_shares (
  entry_id     uuid   not null references entries(id) on delete cascade,
  member_id    uuid   not null references members(id) on delete restrict,

  -- Zero is legitimate — someone present who owes nothing for this bill —
  -- but negative is not: it would manufacture a debt out of a balancing pair.
  amount_minor bigint not null check (amount_minor >= 0),

  -- The original input, scaled: "2:1:1" or "50/30/20". Null for an exact
  -- split, where the amount was the input.
  weight       numeric(24,6),
  primary key (entry_id, member_id)
);

-- ============================================================================
-- The invariant
--
--   sum(payers.amount) = sum(shares.amount) = entries.amount_minor
--
-- A cross-table CHECK is impossible, so this is a DEFERRED constraint trigger:
-- it fires at COMMIT, letting an entry and its children be written in any order
-- inside one transaction.
--
-- It hangs off all THREE tables, and that is the whole point. Hung off the
-- children alone — which is how this started — the invariant only held for a
-- statement that touched a payer or a share, so `update entries set
-- amount_minor = <anything>` committed happily against untouched children, and
-- an entry inserted with no children at all was never checked by anything.
-- Neither goes through upsert_entry, but neither has to: `authenticated` holds
-- INSERT and UPDATE on entries because upsert_entry is SECURITY INVOKER and
-- needs them, so any client that skips the RPC and speaks to PostgREST
-- directly had both. The trigger is what makes the invariant a property of the
-- data rather than of the one code path that happens to respect it.
--
-- This catches every rounding bug, every bad largest-remainder implementation
-- and every partial write, and it is what makes it safe for the client to
-- compute splits.
-- ============================================================================

-- The check itself, addressed by entry id so both sides of the relationship
-- can ask the same question. Extracted rather than duplicated: two copies of
-- an invariant are two chances for one of them to be wrong.
create or replace function assert_balanced(p_entry uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_total bigint;
  v_paid  bigint;
  v_owed  bigint;
begin
  select amount_minor into v_total from entries where id = p_entry;
  if v_total is null then
    return;  -- entry was deleted in the same transaction
  end if;

  select coalesce(sum(amount_minor), 0) into v_paid
    from entry_payers where entry_id = p_entry;
  select coalesce(sum(amount_minor), 0) into v_owed
    from entry_shares where entry_id = p_entry;

  if v_paid <> v_total or v_owed <> v_total then
    raise exception
      'Entry % does not balance: amount=%, paid=%, owed=%',
      p_entry, v_total, v_paid, v_owed
      using errcode = 'check_violation';
  end if;
end;
$$;

-- From a payer or share row, whichever way it moved.
create or replace function assert_entry_balanced()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform assert_balanced(coalesce(new.entry_id, old.entry_id));
  return null;
end;
$$;

-- From the entry itself.
create or replace function assert_entry_row_balanced()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform assert_balanced(new.id);
  return null;
end;
$$;

create constraint trigger trg_payers_balanced
  after insert or update or delete on entry_payers
  deferrable initially deferred
  for each row execute function assert_entry_balanced();

create constraint trigger trg_shares_balanced
  after insert or update or delete on entry_shares
  deferrable initially deferred
  for each row execute function assert_entry_balanced();

-- Deliberately not fired on DELETE: an entry going away takes its payers and
-- shares with it by cascade, and there is nothing left to balance. Soft
-- deletion is an UPDATE and is checked like any other.
create constraint trigger trg_entries_balanced
  after insert or update on entries
  deferrable initially deferred
  for each row execute function assert_entry_row_balanced();

-- ----------------------------------------------------------------------------
-- Column rules for entries, as a trigger rather than a policy.
--
-- The same gap guard_member_update closes for members, and for the same
-- reason: RLS decides which ROWS a statement may touch and cannot say "this
-- column, but only like so", and WITH CHECK cannot see OLD at all. So
-- entries_update, on its own, admits any member of a group to rewrite any
-- column of any entry in it. Three of those were reachable:
--
--   * move an expense into another group you belong to, which leaves its
--     payers and shares naming members of the group it came from — and
--     v_member_balances then reports balances in the destination group for
--     people who are not in it. assert_member_in_group cannot catch this: it
--     fires on the children, and the children did not move.
--   * rewrite created_by, attributing your expense to somebody else.
--     upsert_entry deliberately has no parameter for authorship; this was the
--     way around that.
--   * rewrite created_at or client_key, the second of which is what makes a
--     retried push idempotent rather than a duplicate expense.
--
-- Authorship on INSERT is checked here too. upsert_entry resolves the caller's
-- own member row and writes that, so a direct insert was the only way to name
-- somebody else, and now it is not.
--
-- auth.uid() is null exactly when there is no JWT — a migration, a pgTAP
-- fixture, or the service role — and those are left alone. The scheduled jobs
-- and delete_account() run that way, and each has already checked far more
-- than this trigger could.
-- ----------------------------------------------------------------------------
create or replace function guard_entry_write()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_mine uuid;
begin
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select id into v_mine
      from members
     where group_id = new.group_id
       and profile_id = auth.uid()
       and left_at is null;

    if new.created_by is distinct from v_mine then
      raise exception
        'An expense can only be recorded under your own name in this group'
        using errcode = 'insufficient_privilege';
    end if;

    return new;
  end if;

  if new.group_id is distinct from old.group_id then
    raise exception
      'An expense belongs to the group it was recorded in and cannot be moved'
      using errcode = 'insufficient_privilege';
  end if;

  if new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
     or new.client_key is distinct from old.client_key then
    raise exception 'Who recorded an expense, and when, cannot be rewritten'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

create trigger trg_entries_guard
  before insert or update on entries
  for each row execute function guard_entry_write();

-- ----------------------------------------------------------------------------
-- Members on an entry must belong to that entry's group.
--
-- The foreign key alone only proves the member exists somewhere. Without this,
-- a member of one group could be given a share of another group's expense:
-- real members' balances would be wrong, and it would leak whether a given id
-- exists at all.
-- ----------------------------------------------------------------------------
create or replace function assert_member_in_group()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from entries e
    join members m on m.id = new.member_id
    where e.id = new.entry_id
      and m.group_id = e.group_id
  ) then
    raise exception 'Member % does not belong to the group of entry %',
      new.member_id, new.entry_id
      using errcode = 'foreign_key_violation';
  end if;
  return new;
end;
$$;

create trigger trg_payer_member_in_group
  before insert or update on entry_payers
  for each row execute function assert_member_in_group();

create trigger trg_share_member_in_group
  before insert or update on entry_shares
  for each row execute function assert_member_in_group();

-- ============================================================================
-- Balances — a VIEW. There is no balances table.
--
-- A stored balance has to be kept in step with every edit, soft delete and
-- late-arriving sync, and when it drifts there is no way to tell that it has.
--
-- security_invoker = true is essential. Without it the view executes as its
-- owner and silently bypasses RLS on the underlying tables.
--
-- Grouped by currency: a group can legitimately hold a ₹500 balance AND a €20
-- balance at once. Collapsing them into one display currency is a client-side
-- view, never the model.
-- ============================================================================

create view v_member_balances
with (security_invoker = true) as
select
  group_id,
  member_id,
  currency,
  sum(delta)::bigint as balance_minor
from (
  select e.group_id, p.member_id, e.currency, p.amount_minor as delta
    from entry_payers p
    join entries e on e.id = p.entry_id
   where e.deleted_at is null

  union all

  select e.group_id, s.member_id, e.currency, -s.amount_minor
    from entry_shares s
    join entries e on e.id = s.entry_id
   where e.deleted_at is null
) t
group by group_id, member_id, currency
having sum(delta) <> 0;

-- balance_minor > 0 -> this member is owed money
-- balance_minor < 0 -> this member owes money
-- Per group per currency, these always sum to exactly zero.


-- ----------------------------------------------------------------------------
-- The activity log.
--
-- Editing an expense in place is the right model — the entry row stays the one
-- source of truth, so the balance fold never has to know that history exists —
-- but on its own it is silently destructive. Someone who agreed a bill was
-- ₹400 and settled on it would watch their balance become ₹300 with nothing
-- anywhere to say why, or who did it. That is a trust problem, not a data
-- problem, and it is what this table answers.
--
-- Append-only and deliberately NOT event sourcing. Nothing is ever rebuilt from
-- these rows; they are a record laid alongside the truth, not the truth itself.
-- Rebuilding state from events would mean every read path, the balance fold and
-- sync all had to learn about revisions, for a feature whose entire job is to
-- be readable.
-- ----------------------------------------------------------------------------
create table entry_events (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references entries(id) on delete cascade,

  -- Denormalised from the entry so the group feed is one indexed read rather
  -- than a join, and so an event survives being read after its entry is gone.
  group_id   uuid not null references groups(id) on delete cascade,

  -- A member id, like entries.created_by: authorship is group-scoped, so a
  -- placeholder's edits survive them claiming an account.
  actor_id   uuid not null references members(id) on delete restrict,

  kind       entry_event_kind not null,

  -- {"amount_minor": {"from": 40000, "to": 30000}, ...}. Only what actually
  -- changed, so an edit that touched one field reads as one line.
  --
  -- Null for a create: "everything" is not a diff, and the entry itself is
  -- already the record of what it started as.
  changes    jsonb,

  -- clock_timestamp(), not now(). now() is transaction time and is identical
  -- for every statement in a transaction, so two events written together would
  -- tie and the feed would order them by a random uuid — showing an edit above
  -- the creation it followed. This is a log; it needs the wall clock.
  created_at timestamptz not null default clock_timestamp()
);

-- The feed is "this group, newest first"; the entry history is "this entry, in
-- order". Same trailing id as the entries cursor, and for the same reason: a
-- batch written in one transaction shares a timestamp.
create index idx_entry_events_group on entry_events (group_id, created_at desc, id);
create index idx_entry_events_entry on entry_events (entry_id, created_at);

alter table entry_events enable row level security;

-- ----------------------------------------------------------------------------
-- Recording what happened.
--
-- A trigger rather than a few lines inside upsert_entry, for three reasons.
--
-- OLD is right here. Computing a diff inside the function meant reading the row
-- back before writing it, which is a second query and a race.
--
-- It catches every path. upsert_entry is the only writer today, but an audit
-- trail that only records edits made through the one function that remembered
-- to call it is not an audit trail.
--
-- And it can actually write. upsert_entry is SECURITY INVOKER — deliberately,
-- since that is what subjects the whole write path to RLS — so an insert made
-- inside it is checked against entry_events' policies as the caller. There is
-- no insert policy, by design, so the caller is refused. This function is
-- SECURITY DEFINER and owned by the table owner, so it is the one path that can
-- append, and nothing reachable from a client can fabricate a line of history.
-- ----------------------------------------------------------------------------
create or replace function record_entry_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor   uuid;
  v_kind    entry_event_kind;
  v_changes jsonb;
begin
  -- Authorship is group-scoped, exactly as entries.created_by is, so a
  -- placeholder's edits survive them claiming an account later.
  select id into v_actor
    from members
   where group_id = new.group_id and profile_id = auth.uid() and left_at is null;

  -- Nothing sensible to attribute it to: a service-role backfill, or a
  -- migration. An event with no actor would be a row the feed cannot render.
  if v_actor is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_kind := 'created';
  elsif old.deleted_at is null and new.deleted_at is not null then
    v_kind := 'deleted';
  elsif old.deleted_at is not null and new.deleted_at is null then
    v_kind := 'restored';
  else
    -- Only the fields a person would recognise as "the expense changing".
    -- fx_at moves whenever fx_rate does and would double every currency edit;
    -- updated_at changes on every write by definition, and would make a save
    -- that altered nothing look like an edit.
    select jsonb_strip_nulls(jsonb_build_object(
      'description',  case when old.description  is distinct from new.description
                      then jsonb_build_object('from', old.description,  'to', new.description)  end,
      'amount_minor', case when old.amount_minor is distinct from new.amount_minor
                      then jsonb_build_object('from', old.amount_minor, 'to', new.amount_minor) end,
      'currency',     case when old.currency     is distinct from new.currency
                      then jsonb_build_object('from', old.currency,     'to', new.currency)     end,
      'entry_date',   case when old.entry_date   is distinct from new.entry_date
                      then jsonb_build_object('from', old.entry_date,   'to', new.entry_date)   end,
      'category_id',  case when old.category_id  is distinct from new.category_id
                      then jsonb_build_object('from', old.category_id,  'to', new.category_id)  end,
      'split_kind',   case when old.split_kind   is distinct from new.split_kind
                      then jsonb_build_object('from', old.split_kind,   'to', new.split_kind)   end,
      'notes',        case when old.notes        is distinct from new.notes
                      then jsonb_build_object('from', old.notes,        'to', new.notes)        end
    )) into v_changes;

    -- A save that changed nothing is not an edit. A retried sync and a user
    -- opening the editor and backing out both land here, and a feed full of
    -- "Ravi edited nothing" is worse than no feed at all.
    if v_changes = '{}'::jsonb then
      return new;
    end if;
    v_kind := 'edited';
  end if;

  insert into entry_events (entry_id, group_id, actor_id, kind, changes)
  values (new.id, new.group_id, v_actor, v_kind, v_changes);

  return new;
end;
$$;

-- AFTER, so an event is never written for a statement that then fails.
create trigger trg_entries_record_event
  after insert or update on entries
  for each row execute function record_entry_event();

alter table entries      enable row level security;
alter table entry_payers enable row level security;
alter table entry_shares enable row level security;

-- ----------------------------------------------------------------------------
-- Dormancy.
--
-- What actually keeps this app free is not disk. A group of four with two
-- hundred expenses, children and indexes included, is about 200KB; the free
-- tier's half a gigabyte holds thousands of them, and the binding constraint
-- is monthly active users long before it is storage. So these two jobs are
-- mostly hygiene, and the destructive one is written to almost never fire.
-- ----------------------------------------------------------------------------

-- Hides groups nobody has touched in three months.
--
-- Reversible and non-destructive by design: archiving sets a flag and nothing
-- else. A group that comes back to life un-archives itself the moment someone
-- adds an expense to it, so this can be wrong about a group without ever being
-- a problem for the people in it.
create or replace function archive_dormant_groups(p_after interval default '3 months')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_archived integer;
begin
  with dormant as (
    update groups g
       set archived_at = now()
     where g.archived_at is null
       and coalesce(
             (select max(e.created_at) from entries e where e.group_id = g.id),
             g.created_at
           ) < now() - p_after
    returning 1
  )
  select count(*) into v_archived from dormant;

  return v_archived;
end;
$$;

comment on function archive_dormant_groups is
  'Archives groups with no activity in the given window. Reversible: adding an '
  'entry un-archives. Schedule daily via pg_cron.';

-- Deletes long-dead groups, and only ones where nobody owes anybody anything.
--
-- The settled check is the whole safety of this function. A dormant group is
-- not necessarily a finished one — the most likely reason a group goes quiet
-- with a balance outstanding is that the debt is disputed or forgotten, which
-- is exactly when erasing the record is worst. v_member_balances only lists
-- non-zero balances, so "no rows for this group" is the definition of settled,
-- and a group where money is still owed is simply skipped, indefinitely.
--
-- Torn down explicitly, in dependency order, rather than left to cascade.
-- Deleting the group alone does not work: members and entries both cascade from
-- it, but entry_payers.member_id references members with ON DELETE RESTRICT,
-- and Postgres is free to collect the members first — which it does, and the
-- whole delete fails on a foreign key. Naming the order is also the honest way
-- to write the one operation in this schema that destroys somebody's data: what
-- goes, and in what sequence, is legible rather than emergent.
create or replace function purge_settled_dormant_groups(
  p_after interval default '12 months'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doomed uuid[];
begin
  select coalesce(array_agg(g.id), '{}')
    into v_doomed
    from groups g
   where g.archived_at is not null
     and coalesce(
           (select max(e.created_at) from entries e where e.group_id = g.id),
           g.created_at
         ) < now() - p_after
     and not exists (
       select 1 from v_member_balances b where b.group_id = g.id
     );

  if cardinality(v_doomed) = 0 then
    return 0;
  end if;

  -- entries first, taking payers, shares and events with it by cascade. Doing
  -- it the other way — emptying the children while their entry still stands —
  -- trips the deferred balance check, which quite correctly objects to an
  -- expense that no longer adds up.
  delete from entries where group_id = any(v_doomed);
  delete from invites where group_id = any(v_doomed);
  -- Only now can members go: entry_payers and entry_shares reference them with
  -- ON DELETE RESTRICT, which is what keeps a member who has paid for something
  -- from being deleted out from under it.
  delete from members where group_id = any(v_doomed);
  delete from groups  where id       = any(v_doomed);

  return cardinality(v_doomed);
end;
$$;

comment on function purge_settled_dormant_groups is
  'Deletes archived groups dormant for the window AND fully settled. A group '
  'with any outstanding balance is never purged, however old.';
