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
-- it fires at COMMIT, letting an entry and its children be inserted in any
-- order inside one transaction.
--
-- This single trigger catches every rounding bug, every bad largest-remainder
-- implementation, and every partial write. It is the most valuable thirty lines
-- in the schema, and it is what makes it safe for the client to compute splits.
-- ============================================================================

create or replace function assert_entry_balanced()
returns trigger
language plpgsql
as $$
declare
  v_entry uuid   := coalesce(new.entry_id, old.entry_id);
  v_total bigint;
  v_paid  bigint;
  v_owed  bigint;
begin
  select amount_minor into v_total from entries where id = v_entry;
  if v_total is null then
    return null;  -- entry was deleted in the same transaction
  end if;

  select coalesce(sum(amount_minor), 0) into v_paid
    from entry_payers where entry_id = v_entry;
  select coalesce(sum(amount_minor), 0) into v_owed
    from entry_shares where entry_id = v_entry;

  if v_paid <> v_total or v_owed <> v_total then
    raise exception
      'Entry % does not balance: amount=%, paid=%, owed=%',
      v_entry, v_total, v_paid, v_owed
      using errcode = 'check_violation';
  end if;

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

alter table entries      enable row level security;
alter table entry_payers enable row level security;
alter table entry_shares enable row level security;
