-- ============================================================================
-- Invites, claim tokens, and anonymous-account hygiene.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Invites.
--
-- The link carries a single-use, expiring token — never a raw member_id.
-- A member id in a URL means anyone who ever sees that URL can seize that
-- person's financial identity in the group, retroactively and permanently.
-- The token is a separate secret that can be spent once and then is worthless.
-- ---------------------------------------------------------------------------
create table invites (
  token       uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,

  -- The placeholder slot this link hands over.
  member_id   uuid not null references members(id) on delete cascade,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now(),

  -- A link forwarded into a group chat lives forever; the token must not.
  expires_at  timestamptz not null default now() + interval '14 days',
  redeemed_at timestamptz,
  redeemed_by uuid references profiles(id)
);

create index idx_invites_member on invites (member_id);
create index idx_invites_group  on invites (group_id);

alter table invites enable row level security;

-- Members of a group can see and issue its invites. Note there is no policy
-- allowing a stranger to SELECT an invite: redemption goes through a
-- security-definer function, so possession of the token is the only proof
-- needed and the table itself stays closed.
create policy invites_read on invites
  for select to authenticated using (is_group_member(group_id));

create policy invites_insert on invites
  for insert to authenticated with check (
    is_group_member(group_id) and created_by = auth.uid()
  );

create policy invites_delete on invites
  for delete to authenticated using (is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Issuing an invite.
--
-- Only for a slot nobody has claimed. Handing out a link to an already-claimed
-- member would be an account takeover with extra steps.
-- ---------------------------------------------------------------------------
create or replace function create_invite(
  p_member_id uuid,
  p_ttl interval default interval '14 days'
)
returns invites
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_member  members;
  v_invite  invites;
begin
  select * into v_member from members where id = p_member_id;

  if v_member.id is null then
    raise exception 'No such member %', p_member_id
      using errcode = 'no_data_found';
  end if;
  if not is_group_member(v_member.group_id) then
    raise exception 'Not a member of that group'
      using errcode = 'insufficient_privilege';
  end if;
  if v_member.profile_id is not null then
    raise exception 'That person has already joined'
      using errcode = 'check_violation';
  end if;

  -- One live link per slot: reissuing invalidates whatever was sent before,
  -- so an old link found in a chat history cannot still be spent.
  delete from invites
   where member_id = p_member_id and redeemed_at is null;

  insert into invites (group_id, member_id, created_by, expires_at)
  values (v_member.group_id, p_member_id, auth.uid(), now() + p_ttl)
  returning * into v_invite;

  return v_invite;
end;
$$;

-- ---------------------------------------------------------------------------
-- Redeeming an invite.
--
-- SECURITY DEFINER because the caller is by definition not yet a member and
-- so cannot read the group, the member row, or the invite. The token is the
-- authorisation.
--
-- The whole thing is one transaction and the invite row is locked, so two taps
-- on the same link cannot both succeed.
--
-- The claim itself sets exactly one column. That is the entire payoff of
-- members being group-scoped: no entry, payer or share row is rewritten, and
-- no balance moves. The person was already fully participating; they simply
-- now have an account attached.
-- ---------------------------------------------------------------------------
create or replace function redeem_invite(p_token uuid)
returns members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite invites;
  v_member members;
  v_uid    uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in first'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_invite from invites where token = p_token for update;

  if v_invite.token is null then
    raise exception 'This invite link is not valid'
      using errcode = 'no_data_found';
  end if;
  if v_invite.redeemed_at is not null then
    raise exception 'This invite link has already been used'
      using errcode = 'check_violation';
  end if;
  if v_invite.expires_at < now() then
    raise exception 'This invite link has expired'
      using errcode = 'check_violation';
  end if;

  -- Already in the group under another name: claiming a second slot would give
  -- one person two balances that can never be reconciled.
  if exists (
    select 1 from members
     where group_id = v_invite.group_id and profile_id = v_uid
  ) then
    raise exception 'You are already in this group'
      using errcode = 'unique_violation';
  end if;

  select * into v_member
    from members where id = v_invite.member_id for update;

  if v_member.profile_id is not null then
    raise exception 'Someone has already claimed that place'
      using errcode = 'check_violation';
  end if;

  update members
     set profile_id = v_uid
   where id = v_member.id
  returning * into v_member;

  update invites
     set redeemed_at = now(), redeemed_by = v_uid
   where token = p_token;

  return v_member;
end;
$$;

-- Anyone holding a token may attempt redemption; the function does the rest.
grant execute on function redeem_invite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Anonymous-account hygiene.
--
-- Anonymous sign-in is the default entry path, which means it is also
-- unauthenticated row creation. Anonymous users count toward MAU, so abandoned
-- ones have to be reaped or the cost of the free tier drifts upward forever.
--
-- Only accounts that are genuinely empty are removed: no linked identity, no
-- membership anywhere, and untouched for 30 days. Deleting an anonymous user
-- who is in a group would orphan their place in someone else's ledger.
-- ---------------------------------------------------------------------------
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

-- Scheduled only where pg_cron exists, so this migration still applies on a
-- plain Postgres used for self-hosting.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'opensplit-cleanup-anon',
      '17 3 * * *',
      'select public.cleanup_abandoned_anonymous_users()'
    );
  end if;
end;
$$;
