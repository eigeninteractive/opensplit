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

-- ============================================================================
-- Group links: one link, any number of arrivals.
--
-- The invites above hand over one named slot to one person, and that is the
-- right shape when you know who is coming: your friend opens it and becomes the
-- "Priya" somebody already typed. It is the wrong shape for the case people
-- actually have, which is a trip whose WhatsApp group already exists and whose
-- guest list does not. Naming six placeholders in order to mint six links, and
-- then working out which link belongs to whom in a chat of twelve people, is a
-- worse version of just posting one link.
--
-- So this is bearer authority over membership: whoever holds the token may join
-- the group. That is a genuinely bigger claim than an invite makes, and the
-- design answers it in three ways rather than by adding a wall.
--
--   * One live link per group. Minting revokes the previous one, so the link in
--     a chat is always the current link or no link.
--   * It expires, and it can be revoked outright without minting another.
--   * Creating and revoking are both recorded in group_events, so the group can
--     see the door being opened and closed. An invite that only the person
--     holding it knows about is the thing worth refusing.
--
-- What it deliberately does NOT do is ask anybody to approve an arrival. The
-- moment somebody has decided to join is the moment they are most likely to
-- give up, and a group whose members can all see who walked in has a better
-- remedy than a queue: remove them.
-- ============================================================================

create table group_links (
  token      uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),

  -- Shorter than an invite's fourteen days. A named invite is for one person
  -- who may well open it next week; an open link is for a group forming now,
  -- and the longer it lives the longer a forwarded copy keeps working.
  expires_at timestamptz not null default now() + interval '7 days',

  revoked_at timestamptz
);

create index idx_group_links_group on group_links (group_id);

-- One live link per group, enforced rather than merely maintained by
-- create_group_link. Two members tapping "share" at the same moment would
-- otherwise both insert, and the group would have two live doors when everyone
-- involved believes there is one.
create unique index idx_group_links_one_live
  on group_links (group_id)
  where revoked_at is null;

alter table group_links enable row level security;

-- Members can see their group's link rows. There is deliberately no insert,
-- update or delete policy: everything below is SECURITY DEFINER or INVOKER with
-- its own checks, and the table is closed to direct DML for the same reason
-- invites is.
create policy group_links_read on group_links
  for select to authenticated using (is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Minting one.
-- ---------------------------------------------------------------------------
create or replace function create_group_link(
  p_group_id uuid,
  p_ttl interval default interval '7 days'
)
returns group_links
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_link group_links;
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of that group'
      using errcode = 'insufficient_privilege';
  end if;

  -- Revoked rather than deleted: the previous link's existence is part of the
  -- record, and group_events has a row saying it was created.
  update group_links
     set revoked_at = now()
   where group_id = p_group_id and revoked_at is null;

  -- Clamped for the same reason create_invite clamps: p_ttl comes from the
  -- caller, `authenticated` holds execute, and the expiry is the only thing
  -- stopping a token outliving the reason it was sent.
  insert into group_links (group_id, created_by, expires_at)
  values (p_group_id, auth.uid(), now() + least(p_ttl, interval '30 days'))
  returning * into v_link;

  return v_link;
end;
$$;

comment on function create_group_link is
  'Mints the group''s one live invite link, revoking whatever preceded it.';

create or replace function revoke_group_link(p_group_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not is_group_member(p_group_id) then
    raise exception 'Not a member of that group'
      using errcode = 'insufficient_privilege';
  end if;

  update group_links
     set revoked_at = now()
   where group_id = p_group_id and revoked_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reading one without spending it.
--
-- SECURITY DEFINER and callable with no session, exactly like peek_invite and
-- for the same reason: whoever just tapped the link has not been asked who they
-- are yet, and asking before showing them what they are being asked about is
-- how people end up joining as the wrong account.
--
-- It returns the group's name, its size and who minted the link, and
-- deliberately not the member list. That is the next function, and it needs a
-- session.
-- ---------------------------------------------------------------------------
create or replace function peek_group_link(p_token uuid)
returns table (
  group_id     uuid,
  group_name   text,
  inviter_name text,
  member_count integer,
  is_expired   boolean,
  is_revoked   boolean,
  is_member    boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select g.id,
         g.name,
         p.display_name,
         (select count(*)::int from members
           where group_id = g.id and left_at is null),
         l.expires_at < now(),
         l.revoked_at is not null,
         exists (
           select 1 from members mine
            where mine.group_id = g.id
              and mine.profile_id = auth.uid()
              and mine.left_at is null
         )
    from group_links l
    join groups   g on g.id = l.group_id
    join profiles p on p.id = l.created_by
   where l.token = p_token;
$$;

-- ---------------------------------------------------------------------------
-- The unclaimed places, for somebody deciding whether they are one of them.
--
-- The case this exists for: Priya makes the group and types in the six people
-- on the trip, then posts one link. Without this, everybody who arrives becomes
-- a seventh, eighth and ninth member beside the placeholder that is already
-- them, and somebody has to clean up twelve rows by hand afterwards. With it,
-- arriving asks "are you one of these?" and claiming is the same single-column
-- update redeem_invite performs.
--
-- SECURITY DEFINER, but unlike peek it REQUIRES a session. The names of
-- everybody in a group are more than the link already implies to whoever holds
-- it, and this is called after the arrival has chosen an account rather than
-- before -- which they have to do to join in any case, so it costs the flow
-- nothing.
-- ---------------------------------------------------------------------------
create or replace function list_link_placeholders(p_token uuid)
returns table (member_id uuid, display_name text)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first'
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select m.id, m.display_name
      from group_links l
      join members m on m.group_id = l.group_id
     where l.token = p_token
       and l.revoked_at is null
       and l.expires_at >= now()
       and m.profile_id is null
       and m.left_at is null
     order by m.display_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Walking in.
--
-- SECURITY DEFINER because the caller is by definition not yet a member and so
-- cannot read the group, its members, or the link. The token is the
-- authorisation.
--
-- Two ways through, and they differ by exactly one statement. With a member id
-- it claims that unclaimed placeholder -- the same single-column update
-- redeem_invite makes, and the same payoff: no entry, payer or share row is
-- rewritten and no balance moves, because the person was already fully
-- participating. Without one it inserts a new member row, which is what
-- members_insert RLS refuses to let a non-member do and is the whole reason
-- this has to be a function rather than an insert from the client.
-- ---------------------------------------------------------------------------
create or replace function join_with_link(
  p_token uuid,

  -- The placeholder being claimed, or null to arrive as somebody new.
  p_member_id uuid default null,

  -- Only consulted when p_member_id is null. Falls back to the profile's own
  -- name, which is what somebody who already had an account will have.
  p_display_name text default null
)
returns members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link   group_links;
  v_member members;
  v_uid    uuid := auth.uid();
  v_name   text;
begin
  if v_uid is null then
    raise exception 'Sign in first'
      using errcode = 'insufficient_privilege';
  end if;

  -- Locked, so two taps on one link cannot both pass the checks below.
  select * into v_link from group_links where token = p_token for update;

  if v_link.token is null then
    raise exception 'This invite link is not valid'
      using errcode = 'no_data_found';
  end if;
  if v_link.revoked_at is not null then
    raise exception 'This invite link has been turned off'
      using errcode = 'check_violation';
  end if;
  if v_link.expires_at < now() then
    raise exception 'This invite link has expired'
      using errcode = 'check_violation';
  end if;

  -- One person, one place. Two would be two balances for the same human that
  -- can never be reconciled.
  if exists (
    select 1 from members
     where group_id = v_link.group_id and profile_id = v_uid
  ) then
    raise exception 'You are already in this group'
      using errcode = 'unique_violation';
  end if;

  if p_member_id is not null then
    select * into v_member from members where id = p_member_id for update;

    if v_member.id is null or v_member.group_id <> v_link.group_id then
      raise exception 'That person is not in this group'
        using errcode = 'no_data_found';
    end if;
    if v_member.profile_id is not null then
      raise exception 'Someone has already claimed that place'
        using errcode = 'check_violation';
    end if;
    if v_member.left_at is not null then
      raise exception 'That person has left this group'
        using errcode = 'check_violation';
    end if;

    update members
       set profile_id = v_uid
     where id = v_member.id
    returning * into v_member;

    -- Adopt the name your friends wrote on the placeholder, if you have not
    -- chosen one yourself. Same reasoning as redeem_invite: somebody arriving
    -- on a link is signed in anonymously a moment earlier and has no name at
    -- all, while the group already knows them as whatever was typed.
    update profiles
       set display_name = v_member.display_name
     where id = v_uid and display_name is null;

    return v_member;
  end if;

  -- Nobody to claim: arrive as somebody new.
  --
  -- The name they gave, else the name already on their account, else a
  -- placeholder for one. The final coalesce is outside the query on purpose:
  -- `select into` over a profile row that does not exist leaves v_name null
  -- rather than running the coalesce at all, and members.display_name is NOT
  -- NULL with a non-empty check -- so the join would fail on a constraint
  -- instead of on anything a person could act on.
  select coalesce(
           nullif(trim(coalesce(p_display_name, '')), ''),
           nullif(trim(coalesce(display_name, '')), ''))
    into v_name
    from profiles where id = v_uid;

  v_name := coalesce(
    v_name, nullif(trim(coalesce(p_display_name, '')), ''), 'Someone');

  insert into members (group_id, profile_id, display_name)
  values (v_link.group_id, v_uid, v_name)
  returning * into v_member;

  update profiles
     set display_name = v_name
   where id = v_uid and display_name is null;

  return v_member;
end;
$$;

comment on function join_with_link is
  'Spends a group link: claims an unclaimed placeholder, or adds the caller as '
  'a new member. Never both, and never a second place for one account.';

-- ---------------------------------------------------------------------------
-- The door being opened and closed, on the record.
--
-- The argument for recording this is the argument for the whole feature being
-- acceptable. An open link is the one object in this schema that lets somebody
-- nobody invited personally walk into a group's finances, and a group that
-- cannot see it exists has no way to decide it should not.
-- ---------------------------------------------------------------------------
create or replace function record_link_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind group_event_kind;
begin
  if tg_op = 'INSERT' then
    v_kind := 'link_created';
  elsif new.revoked_at is not null and old.revoked_at is null then
    v_kind := 'link_revoked';
  else
    return null;
  end if;

  insert into group_events (group_id, actor_id, kind, subject_id, payload)
  values (
    new.group_id,
    acting_member(new.group_id),
    v_kind,
    new.token,
    jsonb_build_object('expires_at', new.expires_at)
  );

  return null;
end;
$$;

create trigger trg_group_links_record
  after insert or update on group_links
  for each row execute function record_link_event();
