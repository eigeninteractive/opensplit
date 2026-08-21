-- Version columns for the rows that sync but had none.
--
-- Only `entries` carried updated_at, so the client's pull could do a real
-- last-write-wins on entries and nothing else. Groups and members were fetched
-- wholesale on every sync and applied with an unconditional upsert, which meant
-- a local rename that had not pushed yet was silently overwritten by whatever
-- the server happened to hold. It is cheap and wrong at six members, and both
-- at sixty.
--
-- Categories get one too: without it a group's own category can never be
-- renamed on one device and seen on another.

alter table groups     add column updated_at timestamptz not null default now();
alter table members    add column updated_at timestamptz not null default now();
alter table categories add column updated_at timestamptz not null default now();

-- Maintained by the database rather than by callers. A client that forgets to
-- set it — or sets it from its own clock — would reintroduce exactly the
-- cross-device clock race that server timestamps exist to prevent.
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

-- Delta reads order on (updated_at, id), matching the entries cursor.
create index idx_groups_updated     on groups     (updated_at, id);
create index idx_members_group_updated on members (group_id, updated_at, id);
create index idx_categories_group_updated on categories (group_id, updated_at, id);

-- ---------------------------------------------------------------------------
-- A payment handle that belongs to the group, not to an account.
--
-- profiles.upi_vpa only helps someone who has signed up. The whole point of
-- placeholder members is that a real person can owe and be owed before they
-- have ever heard of the app — and settling with them is exactly when you need
-- their UPI ID. Without this the India-first settle-up flow silently degrades
-- to "type it in yourself" for precisely the members most likely to need it.
--
-- The check matches upi_vpa_format on profiles and upiVpaPattern in Dart.
-- ---------------------------------------------------------------------------
alter table members add column upi_vpa text;

alter table members
  add constraint members_upi_vpa_format
  check (upi_vpa is null or upi_vpa ~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$');
