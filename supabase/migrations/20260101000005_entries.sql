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
-- The sync clock belongs to the server.
--
-- `updated_at` is not a fact about the expense; it is the delta pull's own
-- bookkeeping, and the pull treats it as authoritative. A client able to write
-- it can do two things nobody should be able to do:
--
--   * backdate a change behind everyone's cursor, so an edit is committed on
--     the server and never reaches a single other device;
--   * stamp one in the far future, which pins every member's cursor there and
--     stops the group receiving expenses at all, permanently.
--
-- Both were reachable. `entries` was the one versioned table with no touch
-- trigger -- it had only a column default, which a client can simply override
-- by naming the column.
-- ----------------------------------------------------------------------------
create trigger trg_entries_touch
  before insert or update on entries
  for each row execute function touch_updated_at();

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


-- ============================================================================
-- The record of what happened.
--
-- Editing an expense in place is the right model -- the entry row stays the one
-- source of truth, so the balance fold never has to know that history exists --
-- but on its own it is silently destructive. Someone who agreed a bill was
-- Rs.400 and settled on it would watch their balance move with nothing anywhere
-- to say why, or who did it. That is a trust problem rather than a data one,
-- and it is what this table answers.
--
-- Every committed change to an expense appends one row here, written by the
-- server, holding what the expense looked like AFTER the change. The feed
-- people read is the difference between consecutive rows, computed on the
-- client from two snapshots it did not author.
--
-- WHY SNAPSHOTS RATHER THAN DIFFS
--
-- A diff needs the before-image of the whole expense, and one logical change
-- spans several statements across three tables -- `upsert_entry` replaces
-- payers and shares wholesale. So:
--
--   * a row-level trigger on `entries` has OLD, but knows nothing about the
--     children that carry who owes what;
--   * a statement-level trigger with transition tables sees both images of ONE
--     statement, and delete-then-insert of the shares is two;
--   * a deferred constraint trigger runs once at COMMIT with the whole shape
--     finally coherent, which is the only useful moment -- and by then the
--     before-image is gone.
--
-- SQL offers no "start of a logical change" hook to hang a capture on, so the
-- after-image is the only thing observable at the only moment worth observing.
-- Snapshots are what that constraint leaves, not a preference.
--
-- WHY NO CLIENT MAY WRITE IT
--
-- There is no insert, update or delete grant on this table and no policy for
-- any of them. It is written exclusively by the trigger below.
--
-- That is a stronger guarantee than the append-only-in-your-own-name policy it
-- replaces, and the difference is the whole point. A client that authors its
-- own history can describe a Rs.400 -> Rs.4,000 edit as a ten-rupee correction,
-- and nothing on the server can tell. Worse, it could edit only the SHARES --
-- moving a hundred rupees from itself to a flatmate while the total stays put,
-- which the balance invariant happily accepts -- and write no history at all.
-- Deriving the record here removes the claim from the wire altogether: the
-- client no longer asserts what changed, it renders what the server observed.
--
-- STILL NOT EVENT SOURCING
--
-- Nothing is ever rebuilt from these rows. Balances read `entries` and only
-- `entries`, so a bug anywhere in this machinery can make the feed wrong and
-- can never make a balance wrong.
--
-- The newest snapshot for an expense is, by construction, identical to that
-- expense's current row. That redundancy is deliberate: it is what makes a
-- mismatch -- should one ever appear -- a tamper alarm rather than a merge
-- problem, and it is what lets the history be read without joining against the
-- mutable table it exists to audit.
-- ============================================================================
create table entry_events (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references entries(id) on delete cascade,

  -- Denormalised from the entry so the group feed is one indexed read rather
  -- than a join.
  group_id   uuid not null references groups(id) on delete cascade,

  -- Who was holding the pen, as a member id -- group-scoped like
  -- `entries.created_by`, so a placeholder's edits survive them claiming an
  -- account.
  --
  -- Nullable, and that is not laxness. A change made by something with no
  -- member row -- a future job, an operator at a psql prompt -- must still be
  -- recorded. "Something changed and we cannot say who" is a far better audit
  -- line than silence, and silence is what a NOT NULL here would buy.
  actor_id   uuid references members(id) on delete restrict,

  -- clock_timestamp(), not now(). now() is transaction time and is identical
  -- for every statement in a transaction, so two snapshots written together
  -- would tie and the feed would order them by a random uuid. This is a log; it
  -- needs the wall clock.
  created_at timestamptz not null default clock_timestamp(),

  -- --------------------------------------------------------------------------
  -- The snapshot: everything about the expense a reader would call a change.
  --
  -- `fx_rate` and friends are absent on purpose -- they move whenever the
  -- currency does and would double every currency edit. `updated_at` is absent
  -- because it moves on every write by definition, which would make a save that
  -- altered nothing read as an edit.
  -- --------------------------------------------------------------------------
  description  text        not null,
  currency     char(3)     not null,
  amount_minor bigint      not null,
  entry_date   date        not null,
  split_kind   split_kind  not null,

  -- Plain uuid, deliberately not a foreign key: a snapshot records the category
  -- an expense had at the time, and deleting a category must not rewrite what
  -- happened.
  category_id  uuid,
  notes        text,

  -- Set once the expense is soft-deleted. What makes "deleted" and "restored"
  -- readable off the chain rather than needing a column to assert them.
  deleted_at   timestamptz,

  -- [{"member_id": "...", "amount_minor": 40000}, ...], ordered by member id so
  -- that two snapshots of an unchanged split compare equal with `=`.
  --
  -- This is the half that used to be missing entirely. Who owes what is where
  -- the money actually lives, and a history that recorded only the total could
  -- not see a split being quietly rewritten underneath it.
  payers       jsonb not null,
  shares       jsonb not null
);

-- The feed is "this group, newest first"; an expense's history is "this entry,
-- in order". Same trailing id as the entries cursor, and for the same reason: a
-- batch written in one transaction can share a timestamp.
-- Ascending, matching the order the activity feed is read in: the client asks
-- for `(created_at, id)` strictly after its cursor and orders both ascending.
-- Against a `(created_at desc, id asc)` index that ordering is mixed relative
-- to the query, so neither a forward nor a backward scan satisfies it and
-- Postgres sorts instead -- on the one feed that a device seeing an active
-- group for the first time reads in its entirety.
create index idx_entry_events_group on entry_events (group_id, created_at, id);
create index idx_entry_events_entry on entry_events (entry_id, created_at);

alter table entry_events enable row level security;

-- ----------------------------------------------------------------------------
-- Taking the snapshot.
--
-- SECURITY DEFINER because no caller has -- or should have -- insert on
-- entry_events. This function is the only writer, which is exactly what makes
-- the record worth reading.
-- ----------------------------------------------------------------------------
create or replace function snapshot_entry(p_entry uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry  entries;
  v_payers jsonb;
  v_shares jsonb;
  v_actor  uuid;
  v_last   entry_events;
begin
  select * into v_entry from entries where id = p_entry;

  -- Gone in this same transaction, which only a cascade from the group can do.
  -- The history goes with it; there is nothing left to describe.
  if v_entry.id is null then
    return;
  end if;

  select coalesce(
           jsonb_agg(jsonb_build_object(
             'member_id', member_id, 'amount_minor', amount_minor)
             order by member_id),
           '[]'::jsonb)
    into v_payers
    from entry_payers where entry_id = p_entry;

  select coalesce(
           jsonb_agg(jsonb_build_object(
             'member_id', member_id, 'amount_minor', amount_minor)
             order by member_id),
           '[]'::jsonb)
    into v_shares
    from entry_shares where entry_id = p_entry;

  select * into v_last
    from entry_events
   where entry_id = p_entry
   order by created_at desc, id desc
   limit 1;

  -- Nothing this table records has moved.
  --
  -- Load-bearing, not an optimisation. One edit fires this function once per
  -- affected row across three tables -- replacing four shares fires it five
  -- times -- so without this a single save would read as five separate events.
  -- It is also what makes a re-saved editor and a retried sync produce nothing,
  -- which is the behaviour a feed full of "Ravi edited nothing" needs.
  if v_last.id is not null
     and v_last.description  is not distinct from v_entry.description
     and v_last.currency     is not distinct from v_entry.currency
     and v_last.amount_minor is not distinct from v_entry.amount_minor
     and v_last.entry_date   is not distinct from v_entry.entry_date
     and v_last.split_kind   is not distinct from v_entry.split_kind
     and v_last.category_id  is not distinct from v_entry.category_id
     and v_last.notes        is not distinct from v_entry.notes
     and v_last.deleted_at   is not distinct from v_entry.deleted_at
     and v_last.payers       = v_payers
     and v_last.shares       = v_shares
  then
    return;
  end if;

  -- The caller's own member row, resolved here rather than accepted as an
  -- argument. There is no parameter for it precisely so that no write path can
  -- attribute a change to somebody else.
  select id into v_actor
    from members
   where group_id = v_entry.group_id
     and profile_id = auth.uid()
     and left_at is null;

  insert into entry_events (
    entry_id, group_id, actor_id,
    description, currency, amount_minor, entry_date, split_kind,
    category_id, notes, deleted_at, payers, shares)
  values (
    v_entry.id, v_entry.group_id, v_actor,
    v_entry.description, v_entry.currency, v_entry.amount_minor,
    v_entry.entry_date, v_entry.split_kind, v_entry.category_id,
    v_entry.notes, v_entry.deleted_at, v_payers, v_shares);
end;
$$;

comment on function snapshot_entry is
  'Appends what an expense now looks like to entry_events, unless that is '
  'already what the newest row there says. The only writer of that table.';

create or replace function snapshot_from_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform snapshot_entry(new.id);
  return null;
end;
$$;

create or replace function snapshot_from_child()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform snapshot_entry(coalesce(new.entry_id, old.entry_id));
  return null;
end;
$$;

-- DEFERRED, and hung off all three tables, for precisely the reasons the
-- balance invariant above is: an expense and its children are written in
-- several statements in any order, and the only moment the shape is coherent
-- enough to photograph is COMMIT.
--
-- The children matter most. A change that touches only entry_shares -- moving
-- what one member owes while the total stays put -- is invisible to a trigger
-- on `entries` alone, and it is the single most valuable thing to have on the
-- record, because it is the one edit that moves money without moving any
-- number a casual reader would check.
create constraint trigger trg_entries_snapshot
  after insert or update on entries
  deferrable initially deferred
  for each row execute function snapshot_from_entry();

create constraint trigger trg_payers_snapshot
  after insert or update or delete on entry_payers
  deferrable initially deferred
  for each row execute function snapshot_from_child();

create constraint trigger trg_shares_snapshot
  after insert or update or delete on entry_shares
  deferrable initially deferred
  for each row execute function snapshot_from_child();

-- ----------------------------------------------------------------------------
-- A child moving is the entry moving.
--
-- `updated_at` is what the delta pull cursors on, so a change the column does
-- not reflect is a change no other device ever receives. Rewriting a share
-- without this leaves the server holding one split and every phone in the group
-- holding another, indefinitely and undetectably -- until somebody reinstalls
-- and silently gets the other answer.
--
-- SECURITY DEFINER so it survives the caller losing direct UPDATE on entries.
-- ----------------------------------------------------------------------------
create or replace function touch_parent_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update entries set updated_at = now()
   where id = coalesce(new.entry_id, old.entry_id);
  return null;
end;
$$;

create trigger trg_payers_touch_parent
  after insert or update or delete on entry_payers
  for each row execute function touch_parent_entry();

create trigger trg_shares_touch_parent
  after insert or update or delete on entry_shares
  for each row execute function touch_parent_entry();

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
