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
  -- Nullable, and set null rather than restricting: a group outlives the
  -- account that made it. Somebody deleting their account must not be blocked
  -- by, or take down, a group four other people are still using — so the
  -- honest state is "created by an account that no longer exists".
  --
  -- Only ever an escape hatch for the instant between creating a group and the
  -- creator's own member row landing; see the groups_read and groups_update
  -- policies. Null simply never matches auth.uid(), so it degrades to
  -- membership, which is the check that actually matters.
  created_by       uuid references profiles(id) on delete set null,
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
-- Categories are global reference data. There are no per-group ones, and no
-- way for a client to add one: a category invented on a phone would be an id
-- the server has never heard of, written onto an entry that then reads as
-- uncategorised on every other device. A fixed list that is identical
-- everywhere is what makes "by category" mean the same thing to everyone.
--
-- The ids are fixed rather than generated, because a client has to be able to
-- categorise an expense before it has ever synced. Kept in step with
-- lib/data/local/reference_data.dart.
create table categories (
  id         uuid primary key,
  name       text not null,
  icon       text not null,
  updated_at timestamptz not null default now()
);

insert into categories (id, name, icon) values
  ('e7b1844c-76a3-4d2b-bd81-56a74e11f943', 'Restaurants',            'restaurant'),
  ('afe84b91-6ac5-4ec2-9290-bd18cb8a7605', 'Groceries',              'local_grocery_store'),
  ('ea5dacd7-da9f-49e3-9e99-90a0343be536', 'Drinks & nightlife',     'local_bar'),
  ('1f289d21-ff2f-4382-a4f8-31d6366583fa', 'Accommodation',          'hotel'),
  ('8a682d2e-53f2-4d7f-9217-16e360c3eaa5', 'Flights',                'flight'),
  ('36df7514-5f84-433f-bcce-67a891f61a93', 'Taxi & rideshare',       'local_taxi'),
  ('dff02d03-31fa-476d-b6d4-67c9322c3b50', 'Public transport',       'directions_transit'),
  ('02fa4141-452c-4142-b51b-9374b8a78186', 'Fuel & parking',         'local_gas_station'),
  ('f5676a7a-6c8b-4ac9-bf09-ccc982885153', 'Activities & outings',   'local_activity'),
  ('421962f1-795c-414a-816b-215cb8a942c2', 'Shopping',               'shopping_bag'),
  ('8c66bd37-e243-480d-8277-135105642331', 'Rent',                   'cottage'),
  ('cfb5c503-c424-41d4-a285-a51ab44f0a28', 'Utilities',              'bolt'),
  ('669596e4-88f5-4a66-97d0-a6f5857cc6b0', 'Internet & phone',       'wifi'),
  ('4ea8849c-d298-4a23-91ec-84332bac0a81', 'Household supplies',     'cleaning_services'),
  ('bca2463d-8dc4-45b5-8b86-ef59559e7820', 'Furniture & appliances', 'chair'),
  ('54dd3641-140a-4931-8235-0600d6f34f34', 'Repairs & maintenance',  'handyman'),
  ('1e7958bd-100e-4bc4-8e16-23a5a12f01cd', 'Health & medical',       'medical_services'),
  ('fca7633f-06b4-4492-bbdc-2ef1e850dc1b', 'Gifts & celebrations',   'celebration'),
  ('580f8062-6c94-4997-b9e4-b13d3140a738', 'Subscriptions',          'subscriptions'),
  ('4d6e0094-04e8-4aae-9d93-9aeb7c3fff4e', 'Other',                  'category');

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


create index idx_groups_updated on groups (updated_at, id);
create index idx_members_group_updated on members (group_id, updated_at, id);

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
