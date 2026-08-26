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

-- ---------------------------------------------------------------------------
-- Claiming a registration.
--
-- The token is the primary key, and a device can change hands: somebody signs
-- in as a different account, or reinstalls, and FCM hands back the same
-- registration. A plain upsert cannot express that, because RLS evaluates the
-- UPDATE half against the row already there — which belongs to the previous
-- owner — and refuses. The symptom is a device that quietly stops receiving
-- anything after an account switch, with the row still pointing at the account
-- that left.
--
-- SECURITY DEFINER, so the takeover is possible, and narrow enough that this
-- is safe: it can only ever write auth.uid() into profile_id, so the worst a
-- caller can do is move a registration they physically hold onto themselves —
-- which is the operation. It cannot read one, and it cannot give one away.
-- ---------------------------------------------------------------------------
create or replace function register_device_token(
  p_token    text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first'
      using errcode = 'insufficient_privilege';
  end if;
  if p_platform not in ('android', 'web') then
    raise exception 'Unknown platform %', p_platform
      using errcode = 'check_violation';
  end if;

  insert into device_tokens (token, profile_id, platform, last_seen_at)
  values (p_token, auth.uid(), p_platform, now())
      on conflict (token) do update
      set profile_id   = auth.uid(),
          platform     = excluded.platform,
          last_seen_at = now();
end;
$$;

comment on function register_device_token is
  'Registers this device against the calling account, taking the token over '
  'from a previous owner if it has one. profile_id is always auth.uid().';

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
