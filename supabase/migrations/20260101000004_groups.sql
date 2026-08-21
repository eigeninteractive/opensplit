-- ============================================================================
-- Groups, members and categories.
--
-- THE LOAD-BEARING DECISION: a member is group-scoped and may have no account
-- at all. `profile_id is null` is a placeholder — a real person, added by a
-- friend, who can pay, hold a balance and be settled with before they have
-- ever heard of this app. Claiming an invite sets exactly one column.
--
-- Had financial rows referenced profiles, every person joining a group would
-- be a data migration.
-- ============================================================================

create table groups (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(trim(name)) > 0),
  default_currency char(3) not null references currencies(code),

  -- A 1:1 "direct" split is just a two-member group with this set. There is
  -- deliberately no second system for friends, which would otherwise duplicate
  -- the entire balance and settlement path.
  is_direct        boolean not null default false,
  simplify_debts   boolean not null default true,
  created_by       uuid not null references profiles(id),
  created_at       timestamptz not null default now(),
  archived_at      timestamptz,
  updated_at       timestamptz not null default now()
);

create table members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,

  -- Null means a placeholder. This is the column an invite claim sets.
  profile_id   uuid references profiles(id) on delete set null,
  display_name text not null check (length(trim(display_name)) > 0),
  role         member_role not null default 'member',
  joined_at    timestamptz not null default now(),

  -- Members are never deleted; they leave. A member who has paid for anything
  -- must stay referenceable or their entries stop making sense.
  left_at      timestamptz,

  -- A payment handle for this person in this group.
  --
  -- Group-scoped rather than only on the profile, because a placeholder has no
  -- profile and settling with a placeholder is exactly when the handle is
  -- needed. Falls back to the linked profile's when null.
  upi_vpa      text,

  updated_at   timestamptz not null default now(),

  unique (group_id, profile_id),

  constraint members_upi_vpa_format
    check (upi_vpa is null or upi_vpa ~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$')
);

-- Categories: global presets (group_id null) plus a group's own additions.
--
-- The preset ids are fixed rather than generated. A client has to be able to
-- categorise an expense before it has ever synced, and the category_id it
-- writes must be one the server recognises when the entry finally arrives.
-- Kept in step with lib/data/local/reference_data.dart.
create table categories (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid references groups(id) on delete cascade,
  name       text not null,
  icon       text,
  updated_at timestamptz not null default now()
);

insert into categories (id, group_id, name, icon) values
  ('00000000-0000-4000-8000-000000000001', null, 'Food & Drink',  'utensils'),
  ('00000000-0000-4000-8000-000000000002', null, 'Groceries',     'shopping-cart'),
  ('00000000-0000-4000-8000-000000000003', null, 'Transport',     'car'),
  ('00000000-0000-4000-8000-000000000004', null, 'Accommodation', 'bed'),
  ('00000000-0000-4000-8000-000000000005', null, 'Rent',          'home'),
  ('00000000-0000-4000-8000-000000000006', null, 'Utilities',     'zap'),
  ('00000000-0000-4000-8000-000000000007', null, 'Entertainment', 'film'),
  ('00000000-0000-4000-8000-000000000008', null, 'Shopping',      'shopping-bag'),
  ('00000000-0000-4000-8000-000000000009', null, 'Health',        'heart-pulse'),
  ('00000000-0000-4000-8000-00000000000a', null, 'Other',         'circle-dot');

-- ----------------------------------------------------------------------------
-- Row versioning
--
-- These tables are refetched whole on every pull — a group has one row and a
-- handful of members, so a delta feed would cost more than it saves — but they
-- are applied last-write-wins, not blindly. Without a version the pull would
-- overwrite whatever the device holds, silently discarding an edit made
-- offline that has not pushed yet.
--
-- Maintained by the database rather than by callers. A client that sets it from
-- its own clock would reintroduce exactly the cross-device clock race that
-- server timestamps exist to prevent.
-- ----------------------------------------------------------------------------
create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_groups_touch
  before update on groups
  for each row execute function touch_updated_at();

create trigger trg_members_touch
  before update on members
  for each row execute function touch_updated_at();

create trigger trg_categories_touch
  before update on categories
  for each row execute function touch_updated_at();

create index idx_groups_updated on groups (updated_at, id);
create index idx_members_group_updated on members (group_id, updated_at, id);
create index idx_categories_group_updated on categories (group_id, updated_at, id);

-- Members are read in full on every pull, so this stays cheap as groups grow.
create index idx_members_group_active on members (group_id) where left_at is null;

-- ----------------------------------------------------------------------------
-- Membership predicates.
--
-- THE FOOTGUN: a policy on `members` that itself selects from `members` causes
-- infinite recursion (Postgres 42P17). Every project with group membership hits
-- it. The fix is a SECURITY DEFINER helper, which bypasses RLS on its internal
-- read — that is the entire reason these exist rather than being inline
-- subqueries in the policies.
--
-- They live here, beside the tables they read, and are used both by the
-- policies in 0010 and by the RPCs that gate on membership.
-- ----------------------------------------------------------------------------
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

-- For the window before the creator exists as a member of their own group.
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

alter table groups     enable row level security;
alter table members    enable row level security;
alter table categories enable row level security;
