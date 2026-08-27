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
-- Looking at an invite without spending it.
--
-- Redemption and deciding who you are have to happen in that order, and they
-- used to happen in the wrong one. The app signed every arrival in anonymously
-- and claimed the slot immediately, so somebody who already had an account —
-- the overwhelmingly common case, since invites are how people arrive — had
-- their place taken by a throwaway account, the token spent, and no way in.
-- Signing in afterwards did not help: the member row pointed at the anonymous
-- user, `unique (group_id, profile_id)` refused a second slot, and the invite
-- was already redeemed. The group owner reissuing the link was the only repair.
--
-- So this reads. It shows what the link is for, so the arrival can be asked who
-- they are with something to say yes to, and redeem_invite runs once afterwards
-- as whoever they turned out to be.
--
-- SECURITY DEFINER, and callable with no session at all: at the moment this is
-- called the caller is, by design, nobody yet. It deliberately returns only
-- what the link already implies to whoever holds it — an expired or spent token
-- still describes itself, so the screen can say which of those it is rather
-- than showing "invalid link" for three different reasons.
-- ---------------------------------------------------------------------------
create or replace function peek_invite(p_token uuid)
returns table (
  group_id      uuid,
  group_name    text,
  member_name   text,
  inviter_name  text,
  member_count  integer,
  is_redeemed   boolean,
  is_expired    boolean,

  -- Whether whoever is asking is already in this group under some other name.
  -- False for a caller with no session, which is the common case here.
  -- Reported so the screen can say so instead of offering a Join button that
  -- redeem_invite is going to refuse.
  is_member     boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select g.id,
         g.name,
         m.display_name,
         p.display_name,
         (select count(*)::int from members
           where group_id = g.id and left_at is null),
         i.redeemed_at is not null,
         i.expires_at < now(),
         exists (
           select 1 from members mine
            where mine.group_id = g.id
              and mine.profile_id = auth.uid()
              and mine.left_at is null
         )
    from invites i
    join groups   g on g.id = i.group_id
    join members  m on m.id = i.member_id
    join profiles p on p.id = i.created_by
   where i.token = p_token;
$$;

comment on function peek_invite is
  'Describes an invite without redeeming it, so the arrival can choose an '
  'account before the slot is claimed. Returns no rows for an unknown token.';

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

  -- Clamped, because p_ttl comes from the caller and `authenticated` holds
  -- execute on this function. The expiry is the only thing stopping a token
  -- outliving the reason it was sent, and a modified client asking for
  -- `interval '100 years'` would simply have removed it. The app never passes
  -- this argument at all; it is here so an operator can issue a shorter link,
  -- which the clamp leaves alone.
  insert into invites (group_id, member_id, created_by, expires_at)
  values (v_member.group_id, p_member_id, auth.uid(),
          now() + least(p_ttl, interval '30 days'))
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

  -- Adopt the name your friend wrote on the placeholder, if you have not
  -- chosen one yourself.
  --
  -- Someone arriving on an invite link is signed in anonymously a moment
  -- earlier, and handle_new_user has no email or metadata to work from, so
  -- their profile has no name at all. Meanwhile the group already knows them
  -- as 'Priya', because that is what the person who invited them typed. Taking
  -- that name means they appear as themselves from the first screen instead of
  -- as a stranger, and it is theirs to change afterwards on the Account page.
  --
  -- Guarded on null rather than on a sentinel: this used to compare against the
  -- literal 'Someone' that handle_new_user invented, which could not tell a
  -- name nobody chose from a name somebody genuinely typed. Null says exactly
  -- one thing, so a name the user has actually set is never overwritten by
  -- whatever a friend guessed.
  update profiles
     set display_name = v_member.display_name
   where id = v_uid and display_name is null;

  update invites
     set redeemed_at = now(), redeemed_by = v_uid
   where token = p_token;

  return v_member;
end;
$$;
