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

-- ---------------------------------------------------------------------------
-- Waking the other devices.
--
-- A trigger, declared here, rather than a Database Webhook created in the
-- dashboard. A Supabase webhook is not a different mechanism — it is a row in
-- the dashboard that creates exactly this trigger, calling
-- `supabase_functions.http_request()`, which is itself a wrapper over pg_net.
-- The only real difference is where it lives, and four things follow from
-- getting that wrong:
--
--   * It would be the one piece of production behaviour not in a migration.
--     `db reset` drops it, nothing recreates it, and the symptom is silence —
--     notifications simply stop, which is the failure this schema keeps
--     designing against.
--   * The shared secret would be pasted into dashboard config, when
--     app_settings already holds fx_fetch_secret for exactly this purpose.
--   * The function URL would be written down once per environment, by hand.
--   * `supabase_functions` is Supabase's own schema. pg_net is not. This is
--     the difference between a self-hosted port being a weekend and being a
--     rewrite, which is a promise the README makes.
--
-- It is a trigger rather than a call inside upsert_entry for the same reason
-- the balance check hangs off the table rather than the RPC: upsert_entry is
-- the only writer today, and a fan-out that only fires for the one path that
-- remembered to call it is not a fan-out.
--
-- The payload is built by hand, and deliberately carries three ids and nothing
-- else. `supabase_functions.http_request` sends `to_jsonb(new)` — the whole
-- row, description and notes included — which contradicts the principle at the
-- top of this file: the message carries ids, and the device says the rest.
-- Writing it here is what makes that true of the wire as well as of FCM.
--
-- Fire and forget, like trigger_fx_fetch: pg_net queues the request and returns
-- immediately, so a slow function can never hold up somebody saving an expense.
-- The queue insert is transactional, so an entry that rolls back takes its
-- notification with it.
-- ---------------------------------------------------------------------------
create or replace function notify_entry_created()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url    text;
  v_secret text;
begin
  select value into v_url
    from app_settings where key = 'notify_function_url';
  select value into v_secret
    from app_settings where key = 'notify_webhook_secret';

  -- Unconfigured is a supported state, not an error. A deployment with no push
  -- set up still records expenses; it just does not wake anybody. Raising here
  -- would make the fan-out a precondition for saving an expense at all.
  if v_url is null or v_secret is null then
    return null;
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    return null;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', v_secret
    ),
    -- Shaped like the webhook payload the function already parses, so the
    -- Edge Function is unchanged and its `type`/`table` guard still means
    -- something if this is ever pointed at another table.
    body    := jsonb_build_object(
      'type',  'INSERT',
      'table', tg_table_name,
      'record', jsonb_build_object(
        'id',         new.id,
        'group_id',   new.group_id,
        'created_by', new.created_by
      )
    )
  );

  return null;
end;
$$;

comment on function notify_entry_created is
  'Posts an entry''s ids to the notify-entry Edge Function so the other '
  'members'' devices wake and sync. No-ops until notify_function_url and '
  'notify_webhook_secret are set in app_settings.';

create trigger trg_entries_notify
  after insert on entries
  for each row execute function notify_entry_created();
