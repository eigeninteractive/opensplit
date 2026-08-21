-- ============================================================================
-- Expense splitting — initial schema
-- Postgres 15+ / Supabase
--
-- Core principles:
--   1. Money is bigint minor units. Never float, never numeric-for-money.
--   2. Balances are DERIVED. There is no balances table, ever.
--   3. Members are group-scoped identities, optionally linked to a profile.
--      This is what lets you add "Arun" before Arun installs the app.
--   4. Every entry must balance: sum(payers) = sum(shares) = amount.
--      Enforced by a deferred constraint trigger, not by hope.
-- ============================================================================

create extension if not exists pgcrypto;

-- ============================================================================
-- Enums
-- ============================================================================

create type entry_kind as enum ('expense', 'settlement');

create type split_kind as enum ('equal', 'exact', 'shares', 'percent');
-- 'equal'   -> weights all 1, amounts resolved by largest-remainder
-- 'exact'   -> user typed each amount; weight is null
-- 'shares'  -> weight = share count (2:1:1)
-- 'percent' -> weight = percentage (must sum to 100)

create type member_role as enum ('owner', 'member');

-- ============================================================================
-- Reference: currencies
--
-- The exponent is NOT always 2. JPY/KRW = 0, KWD/BHD/JOD = 3.
-- Hardcoding *100 in the client is a bug you will ship. Read it from here.
-- ============================================================================

create table currencies (
  code      char(3) primary key,
  exponent  smallint not null check (exponent between 0 and 4),
  symbol    text,
  name      text not null
);

insert into currencies (code, exponent, symbol, name) values
  ('INR', 2, '₹',  'Indian Rupee'),
  ('USD', 2, '$',  'US Dollar'),
  ('EUR', 2, '€',  'Euro'),
  ('GBP', 2, '£',  'Pound Sterling'),
  ('SGD', 2, 'S$', 'Singapore Dollar'),
  ('AED', 2, 'د.إ','UAE Dirham'),
  ('AUD', 2, 'A$', 'Australian Dollar'),
  ('JPY', 0, '¥',  'Japanese Yen'),
  ('KRW', 0, '₩',  'South Korean Won'),
  ('VND', 0, '₫',  'Vietnamese Dong'),
  ('IDR', 2, 'Rp', 'Indonesian Rupiah'),
  ('THB', 2, '฿',  'Thai Baht'),
  ('LKR', 2, 'Rs', 'Sri Lankan Rupee'),
  ('NPR', 2, 'Rs', 'Nepalese Rupee'),
  ('KWD', 3, 'د.ك','Kuwaiti Dinar'),
  ('BHD', 3, '.د.ب','Bahraini Dinar');

-- ============================================================================
-- Profiles — mirrors auth.users
-- ============================================================================

create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url   text,
  created_at   timestamptz not null default now()
);

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'display_name',
      split_part(new.email, '@', 1),
      'Someone'
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================================
-- Groups
--
-- A 1:1 "direct" relationship is just a two-member group with is_direct=true.
-- Do not build a second system for friends.
-- ============================================================================

create table groups (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(trim(name)) > 0),
  default_currency char(3) not null references currencies(code),
  is_direct        boolean not null default false,
  simplify_debts   boolean not null default true,
  created_by       uuid not null references profiles(id),
  created_at       timestamptz not null default now(),
  archived_at      timestamptz
);

-- ============================================================================
-- Members — THE key modelling decision
--
-- A member belongs to exactly one group and may or may not be linked to a
-- profile. profile_id IS NULL means a placeholder ("Arun", who hasn't signed
-- up). All financial rows reference member_id, never profile_id.
--
-- Consequence: when Arun signs up and claims his slot you set profile_id and
-- touch nothing else. No rewriting of entries, no balance migration.
--
-- The unique constraint uses default NULLS DISTINCT, so a group can hold many
-- placeholders but a given profile can only join once.
-- ============================================================================

create table members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,
  profile_id   uuid references profiles(id) on delete set null,
  display_name text not null check (length(trim(display_name)) > 0),
  role         member_role not null default 'member',
  joined_at    timestamptz not null default now(),
  left_at      timestamptz,
  unique (group_id, profile_id)
);

-- ============================================================================
-- Categories — group-scoped overrides, NULL group_id = global preset
-- ============================================================================

create table categories (
  id       uuid primary key default gen_random_uuid(),
  group_id uuid references groups(id) on delete cascade,
  name     text not null,
  icon     text
);

insert into categories (group_id, name, icon) values
  (null, 'Food & Drink',  'utensils'),
  (null, 'Groceries',     'shopping-cart'),
  (null, 'Transport',     'car'),
  (null, 'Accommodation', 'bed'),
  (null, 'Rent',          'home'),
  (null, 'Utilities',     'zap'),
  (null, 'Entertainment', 'film'),
  (null, 'Shopping',      'shopping-bag'),
  (null, 'Health',        'heart-pulse'),
  (null, 'Other',         'circle-dot');

-- ============================================================================
-- Entries
--
-- kind='settlement' is one payer + one share. Same table, because it
-- participates in the identical balance fold. Excluded from spend analytics.
--
-- fx_rate is a DISPLAY snapshot captured at entry time. Balances are always
-- computed per-currency from amount_minor. Never convert on write.
-- ============================================================================

create table entries (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  kind          entry_kind not null default 'expense',
  description   text not null default '',
  category_id   uuid references categories(id) on delete set null,

  currency      char(3) not null references currencies(code),
  amount_minor  bigint not null check (amount_minor > 0),

  entry_date    date not null default current_date,
  split_kind    split_kind not null default 'equal',

  fx_rate       numeric(24,12),
  fx_source     text,
  fx_at         timestamptz,

  notes         text,
  receipt_path  text,

  created_by    uuid not null references members(id) on delete restrict,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,

  -- offline clients generate this so a retried sync is idempotent
  client_key    uuid,
  unique (group_id, client_key)
);

-- ============================================================================
-- Payers and shares
--
-- entry_payers is a TABLE, not a paid_by column. Multiple payers on one bill
-- is common ("I got the food, you got the drinks") and is where every
-- simple clone falls over.
--
-- entry_shares stores BOTH:
--   amount_minor -> the resolved amount (immutable historical fact)
--   weight       -> the original input, so "2:1:1" is re-editable
--
-- Storing only the rule means a future rounding fix retroactively changes
-- settled balances. Storing only the amount means you can't re-edit. Store both.
--
-- on delete restrict: a member with financial history can never be deleted.
-- Use members.left_at instead.
-- ============================================================================

create table entry_payers (
  entry_id     uuid   not null references entries(id) on delete cascade,
  member_id    uuid   not null references members(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  primary key (entry_id, member_id)
);

create table entry_shares (
  entry_id     uuid   not null references entries(id) on delete cascade,
  member_id    uuid   not null references members(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  weight       numeric(24,6),
  primary key (entry_id, member_id)
);

-- ============================================================================
-- The invariant
--
-- sum(payers.amount) = sum(shares.amount) = entries.amount_minor
--
-- A cross-table CHECK is impossible, so this is a DEFERRED constraint trigger:
-- it fires at COMMIT, letting you insert entry -> payers -> shares in any
-- order inside one transaction.
--
-- This single trigger catches every rounding bug, every bad largest-remainder
-- implementation, and every partial write. It is the most valuable 30 lines
-- in the schema.
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

-- Members on an entry must belong to that entry's group.
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
-- security_invoker = true is essential. Without it the view executes as its
-- owner and silently bypasses RLS on the underlying tables.
--
-- Note the grouping includes currency: a group can legitimately hold a
-- ₹500 balance AND a €20 balance at the same time. Collapsing them into one
-- display currency is a client-side view, never the model.
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
-- RLS
--
-- THE FOOTGUN: a policy on `members` that itself selects from `members`
-- causes infinite recursion (Postgres error 42P17). Every Supabase project
-- with group membership hits this.
--
-- Fix: a SECURITY DEFINER helper that bypasses RLS on its internal read.
-- ============================================================================

create or replace function is_group_member(gid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from members
     where group_id = gid
       and profile_id = auth.uid()
       and left_at is null
  );
$$;

create or replace function is_group_owner(gid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from members
     where group_id = gid
       and profile_id = auth.uid()
       and role = 'owner'
       and left_at is null
  );
$$;

alter table profiles      enable row level security;
alter table groups        enable row level security;
alter table members       enable row level security;
alter table categories    enable row level security;
alter table entries       enable row level security;
alter table entry_payers  enable row level security;
alter table entry_shares  enable row level security;
alter table currencies    enable row level security;

-- currencies: public reference data
create policy currencies_read on currencies
  for select to authenticated using (true);

-- profiles: yourself, plus anyone you share a group with
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

-- groups
create policy groups_read on groups
  for select to authenticated using (is_group_member(id));

create policy groups_insert on groups
  for insert to authenticated with check (created_by = auth.uid());

create policy groups_update on groups
  for update to authenticated using (is_group_owner(id));

-- members
create policy members_read on members
  for select to authenticated using (is_group_member(group_id));

create policy members_write on members
  for all to authenticated
  using (is_group_member(group_id))
  with check (is_group_member(group_id));

-- categories: global presets plus your own groups'
create policy categories_read on categories
  for select to authenticated
  using (group_id is null or is_group_member(group_id));

create policy categories_write on categories
  for all to authenticated
  using (group_id is not null and is_group_member(group_id))
  with check (group_id is not null and is_group_member(group_id));

-- entries
create policy entries_read on entries
  for select to authenticated using (is_group_member(group_id));

create policy entries_write on entries
  for all to authenticated
  using (is_group_member(group_id))
  with check (is_group_member(group_id));

-- payers / shares: inherit access from the parent entry
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

-- ============================================================================
-- Write path: one RPC, one transaction
--
-- The client never writes entries/payers/shares in three separate calls.
-- That would leave torn state on a dropped connection and defeat the
-- deferred trigger's purpose.
--
-- payers / shares are jsonb arrays:
--   [{"member_id":"...","amount_minor":1200}]
--   [{"member_id":"...","amount_minor":400,"weight":1}]
-- ============================================================================

create or replace function upsert_entry(
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
  p_entry_id    uuid        default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_entry_id uuid;
  v_member   uuid;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of group %', p_group_id
      using errcode = 'insufficient_privilege';
  end if;

  select id into v_member
    from members
   where group_id = p_group_id and profile_id = auth.uid() and left_at is null;

  if p_entry_id is null then
    insert into entries (
      group_id, kind, description, category_id, currency, amount_minor,
      entry_date, split_kind, fx_rate, fx_source, fx_at, notes,
      created_by, client_key
    ) values (
      p_group_id, p_kind, p_description, p_category_id, p_currency, p_amount,
      p_entry_date, p_split_kind, p_fx_rate, p_fx_source,
      case when p_fx_rate is not null then now() end, p_notes,
      v_member, p_client_key
    )
    on conflict (group_id, client_key) do update
      set description = excluded.description  -- idempotent retry
    returning id into v_entry_id;
  else
    update entries set
      description  = p_description,
      category_id  = p_category_id,
      currency     = p_currency,
      amount_minor = p_amount,
      entry_date   = p_entry_date,
      split_kind   = p_split_kind,
      notes        = p_notes,
      updated_at   = now()
    where id = p_entry_id and group_id = p_group_id
    returning id into v_entry_id;

    delete from entry_payers where entry_id = v_entry_id;
    delete from entry_shares where entry_id = v_entry_id;
  end if;

  insert into entry_payers (entry_id, member_id, amount_minor)
  select v_entry_id,
         (x->>'member_id')::uuid,
         (x->>'amount_minor')::bigint
    from jsonb_array_elements(p_payers) x;

  insert into entry_shares (entry_id, member_id, amount_minor, weight)
  select v_entry_id,
         (x->>'member_id')::uuid,
         (x->>'amount_minor')::bigint,
         (x->>'weight')::numeric
    from jsonb_array_elements(p_shares) x;

  -- deferred triggers fire here at commit and reject anything unbalanced
  return v_entry_id;
end;
$$;

-- Soft delete only. Financial rows are never physically removed.
create or replace function delete_entry(p_entry_id uuid)
returns void
language sql
security invoker
set search_path = public
as $$
  update entries set deleted_at = now(), updated_at = now()
   where id = p_entry_id and deleted_at is null;
$$;

-- ============================================================================
-- Indexes
-- ============================================================================

create index idx_entries_group_date
  on entries (group_id, entry_date desc, created_at desc)
  where deleted_at is null;

create index idx_entries_category  on entries (category_id) where deleted_at is null;
create index idx_payers_member     on entry_payers (member_id);
create index idx_shares_member     on entry_shares (member_id);
create index idx_members_profile   on members (profile_id) where left_at is null;
create index idx_members_group     on members (group_id);

-- ============================================================================
-- Realtime
-- ============================================================================

alter publication supabase_realtime add table entries;
alter publication supabase_realtime add table entry_payers;
alter publication supabase_realtime add table entry_shares;
alter publication supabase_realtime add table members;

-- ============================================================================
-- Notes for the client
--
-- SPLITTING ARITHMETIC lives in Dart, not here. Use largest-remainder on
-- integer minor units with a deterministic tiebreak (sort by member_id) so
-- every device produces identical paise. The deferred trigger is your
-- server-side backstop, not your algorithm.
--
-- SIMPLIFY DEBTS is computed client-side from v_member_balances: net each
-- member per currency, then greedily match the largest creditor against the
-- largest debtor. Run it per currency independently. It is a VIEW over
-- balances and must never write rows -- you have to be able to drill from
-- "you owe Arun ₹340" back to the entries that produced it.
--
-- CURRENCY EXPONENT comes from the currencies table. Never assume 2.
-- ============================================================================
