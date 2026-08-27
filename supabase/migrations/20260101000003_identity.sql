-- ============================================================================
-- Identity.
--
-- A profile is an account. It is deliberately NOT what financial rows point
-- at — that is `members`, which is group-scoped — so that someone can owe and
-- be owed before they have ever heard of this app.
-- ============================================================================

create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,

  -- Null means nobody has chosen one yet, and that is a state worth being able
  -- to represent.
  --
  -- This used to be `not null`, which forced handle_new_user to invent a name
  -- for anyone signing up without one — 'Someone' for every guest. The app then
  -- could not tell an invented name from a chosen one, so it asked for a name
  -- again in the new-group sheet and wrote the answer back to the account as a
  -- side effect of making a group. Three places set one name, and none of them
  -- could say whether it had been set.
  --
  -- Nullable makes the question answerable exactly once: if this is null, ask;
  -- otherwise never ask again. Non-empty when it is present, so 'set to blank'
  -- is not a third state on top of the two.
  display_name text check (
    display_name is null or length(trim(display_name)) > 0
  ),
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
  -- nullif on each candidate, not just coalesce over them. An identity
  -- provider that supplies display_name as an empty string, and an account
  -- with no email at all, both produce '' rather than null — which coalesce
  -- would happily accept and the non-empty check would then reject, failing
  -- the signup itself.
  --
  -- No final fallback. If neither the provider nor the email says who this is,
  -- then nobody has said, and the honest record of that is null — the app asks
  -- once and stops. Inventing 'Someone' here is what made a chosen name and an
  -- assigned one indistinguishable everywhere downstream.
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), '')
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

-- INSERT as well as UPDATE, and the insert half is the one that matters.
--
-- A column default is not a guarantee: `authenticated` holds an INSERT grant on
-- this table and profiles_insert admits `id = auth.uid()`, so a client that
-- reaches the insert path can supply its own updated_at. One row stamped in the
-- year 3000 pins every co-member's profiles cursor there and the feed stops --
-- names and UPI handles stop travelling, permanently and silently.
--
-- handle_new_user creates the row on signup, so today the insert path is only
-- reachable for an account whose profile has been deleted. That is one row away
-- from being reachable, and it is the same hole already closed on groups and
-- members. The server owns this clock on every path or it does not own it.
create trigger trg_profiles_touch before insert or update on profiles
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

-- ---------------------------------------------------------------------------
-- Deleting an account.
--
-- Required by Play policy for any app that lets people create an account, and
-- required in-app rather than only by email. It is also the harder half of the
-- promise this app makes about your data, so it is worth being exact about
-- what it does and does not remove.
--
-- It does NOT remove other people's ledgers. Money you paid, money you owe and
-- the settlements between you are facts about *their* group as much as yours,
-- and erasing your side of them would leave everybody else's balances wrong
-- with nothing to explain it. What happens instead is the thing this schema was
-- built for: `members.profile_id` is `on delete set null`, and null means
-- placeholder — so deleting the profile demotes every membership to exactly the
-- state of somebody a friend added who never signed up. The name stays,
-- because it is the name your co-members recorded and read their own history
-- by; the account behind it is gone.
--
-- A group where you were the only account holder is different: nobody left can
-- ever read it again, because every read policy goes through a member row with
-- a profile. Leaving it would mean holding your expense descriptions forever in
-- a group with no living reader, which is the opposite of what was asked for.
-- Those are deleted outright.
--
-- Entries go before invites, members and the group itself, and that ordering is
-- load-bearing: entries cascade to their payers and shares, so the deferred
-- balance trigger never sees a parent without children, and entry_payers
-- references members with ON DELETE RESTRICT, so the members cannot go until
-- the expenses naming them have.
create or replace function delete_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid     uuid := auth.uid();
  v_orphans uuid[];
begin
  if v_uid is null then
    raise exception 'There is no account signed in to delete.'
      using errcode = '42501';
  end if;

  -- Groups this account belongs to that no other account belongs to.
  -- Placeholders do not count: nobody can sign in as one.
  select coalesce(array_agg(g.id), '{}')
    into v_orphans
    from groups g
   where exists (
           select 1 from members m
            where m.group_id = g.id and m.profile_id = v_uid)
     and not exists (
           select 1 from members m
            where m.group_id = g.id
              and m.profile_id is not null
              and m.profile_id <> v_uid);

  delete from entries where group_id = any(v_orphans);
  delete from invites where group_id = any(v_orphans);
  delete from members where group_id = any(v_orphans);
  delete from groups  where id       = any(v_orphans);

  -- Invites reference profiles with no ON DELETE action of their own, so they
  -- hold the profile row hostage. An invite this account minted is spent or
  -- worthless either way; one it redeemed only records who redeemed it.
  delete from invites where created_by = v_uid;
  update invites set redeemed_by = null where redeemed_by = v_uid;

  delete from device_tokens where profile_id = v_uid;

  -- profiles cascades from auth.users, and members.profile_id sets null from
  -- profiles. Deleting the user is therefore what demotes every remaining
  -- membership to a placeholder.
  delete from auth.users where id = v_uid;
end;
$$;

comment on function delete_account is
  'Deletes the calling account: its profile, identities, sessions and push '
  'registrations, plus any group nobody else could still read. Memberships '
  'elsewhere become placeholders, so co-members'' balances and history are '
  'unchanged.';
