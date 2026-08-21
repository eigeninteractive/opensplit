-- ============================================================================
-- Device tokens for push.
--
-- The notification pattern here is notification-as-sync-trigger: the server
-- sends a data-only message carrying almost nothing, the client wakes, pulls
-- the delta, computes, and posts a LOCAL notification.
--
-- The text is therefore produced by the same Dart that renders the screen, so
-- the notification and the app can never disagree. A server-side formatter
-- would be a second implementation of currency exponents, rounding and split
-- arithmetic, quietly drifting from the first — and it would need to know each
-- recipient's share, which is exactly the computation this architecture keeps
-- on the device.
-- ============================================================================

create table device_tokens (
  token       text primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,

  -- 'android' | 'web'. iOS is v2.
  platform    text not null,
  created_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index idx_device_tokens_profile on device_tokens (profile_id);

alter table device_tokens enable row level security;

-- Strictly your own. A token is a capability to interrupt someone's phone; it
-- must never be readable by anyone else, including people in your groups.
create policy device_tokens_own on device_tokens
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

grant select, insert, update, delete on device_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- Who should be woken for an entry.
--
-- SECURITY DEFINER and callable only by the service role: it deliberately reads
-- tokens belonging to other people, which no user-facing policy allows.
--
-- The author is excluded — waking someone for something they just typed is the
-- fastest way to get notifications turned off.
-- ---------------------------------------------------------------------------
create or replace function tokens_for_entry(p_entry_id uuid)
returns table (token text, platform text)
language sql
security definer
set search_path = public
stable
as $$
  select dt.token, dt.platform
    from entries e
    join members m       on m.group_id = e.group_id and m.left_at is null
    join device_tokens dt on dt.profile_id = m.profile_id
   where e.id = p_entry_id
     and m.profile_id is not null
     and m.id <> e.created_by;
$$;

revoke execute on function tokens_for_entry(uuid) from public, anon, authenticated;
grant execute on function tokens_for_entry(uuid) to service_role;
