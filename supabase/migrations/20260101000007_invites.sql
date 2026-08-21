-- ============================================================================
-- Invites.
--
-- An invite hands over one placeholder slot. Possession of the token is the
-- only proof required, so redemption goes through a SECURITY DEFINER function
-- and the table itself stays closed — there is deliberately no policy letting a
-- stranger read an invite row.
--
-- Claiming sets exactly one column, members.profile_id. Nothing about the
-- group's history changes, which is the entire payoff of members being
-- group-scoped rather than auth users.
-- ============================================================================

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
