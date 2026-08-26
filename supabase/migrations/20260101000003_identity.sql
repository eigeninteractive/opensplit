-- ============================================================================
-- Identity.
--
-- A profile is an account. It is deliberately NOT what financial rows point
-- at — that is `members`, which is group-scoped — so that someone can owe and
-- be owed before they have ever heard of this app.
-- ============================================================================

create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url   text,

  -- UPI virtual payment address, for the settle-up handoff. Personal rather
  -- than group-scoped, and exposed to co-members through profiles_read. The
  -- check mirrors the VPA grammar: <handle>@<psp>.
  upi_vpa      text,

  created_at   timestamptz not null default now(),

  -- The delta cursor for the profiles pull.
  --
  -- A profile is no longer only your own business: display_name and upi_vpa are
  -- the account-level truth that every co-member reads, so other devices have
  -- to be able to ask what changed since they last looked. Without this column
  -- there is no cursor and the only way to refresh a name is to fetch every
  -- profile in every group, every sync.
  updated_at   timestamptz not null default now(),

  constraint upi_vpa_format
    check (upi_vpa is null or upi_vpa ~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$')
);

-- A profile row exists for every account from the moment it is created, so no
-- other code path has to cope with a signed-in user who has no profile.
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

-- Maintained server-side rather than trusted from the client, for the same
-- reason entries.updated_at is: two devices with skewed clocks must not be able
-- to settle a conflict between themselves, and a client that forgets to send it
-- would go invisible to every other device's cursor.
create or replace function touch_profile()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_profiles_touch before update on profiles
  for each row execute function touch_profile();

-- ----------------------------------------------------------------------------
-- Anonymous-account hygiene.
--
-- Anonymous sign-in is the default entry path, which means it is also
-- unauthenticated row creation. Anonymous users count toward MAU, so abandoned
-- ones have to be reaped or the cost of the free tier drifts upward forever.
--
-- Only accounts that are genuinely empty are removed: no linked identity, no
-- membership anywhere, and untouched for 30 days. Deleting an anonymous user
-- who is in a group would orphan their place in someone else's ledger.
-- ----------------------------------------------------------------------------
create or replace function cleanup_abandoned_anonymous_users()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_deleted integer;
begin
  with doomed as (
    delete from auth.users u
     where u.is_anonymous
       and u.created_at < now() - interval '30 days'
       and not exists (
         select 1 from auth.identities i where i.user_id = u.id
       )
       and not exists (
         select 1 from public.members m where m.profile_id = u.id
       )
    returning 1
  )
  select count(*) into v_deleted from doomed;

  return v_deleted;
end;
$$;

comment on function cleanup_abandoned_anonymous_users is
  'Reaps empty anonymous accounts. Schedule daily via pg_cron. Deliberately '
  'skips anyone who belongs to a group, however old the account is.';

alter table profiles enable row level security;
