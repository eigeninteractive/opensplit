import { and, eq, isNull, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { GroupLink, Invite, LinkPreview, Member, Placeholder } from "../../schemas/ledger";
import { append } from "./events";
import { refuse } from "./refusal";
import { type MemberRow, nextSeq, requireMember, requireMeta, type Tx } from "./store";

/**
 * Getting into a group.
 *
 * Two doors, and they are genuinely different claims.
 *
 * An **invite** hands over one named slot to one person: your friend opens it
 * and becomes the "Priya" somebody already typed. Possession of the token is
 * the only proof required, and claiming it sets exactly one column —
 * `profileId` on a member row that was already fully participating. No entry,
 * payer or share is rewritten and no balance moves, which is the entire payoff
 * of members being group-scoped rather than accounts.
 *
 * A **group link** is bearer authority over membership: whoever holds it may
 * join. That is a bigger claim, and it is answered by making the door visible
 * rather than by adding a wall — one live link at a time, an expiry, an
 * explicit revoke, and both minting and revoking on the record. What it
 * deliberately does not do is ask anybody to approve an arrival: the moment
 * somebody has decided to join is the moment they are most likely to give up,
 * and a group whose members can all see who walked in has a better remedy than
 * a queue.
 *
 * ## One peek, one join
 *
 * Two kinds of link and two operations, not one pair of each. To the person
 * holding a URL it is one thing — I tapped a link, tell me what it is, then
 * let me in — and the token itself says which kind it is, so the caller should
 * not have to know before asking. Splitting it by kind instead would be four
 * entry points and a decision the client is not equipped to make.
 *
 * ## Peeking before deciding who you are
 *
 * Deciding who you are has to come before redemption, or somebody who already
 * has an account could have their place taken by a throwaway one. `peek` is
 * callable with no session at all, because at that moment the caller is, by
 * design, nobody yet.
 */

/** Clamped, because the caller supplies it and expiry is the only protection a bearer token has. */
const MAX_TTL = 30 * 24 * 60 * 60 * 1000;
const INVITE_TTL = 14 * 24 * 60 * 60 * 1000;

/**
 * Shorter than an invite's fourteen days. A named invite is for one person who
 * may well open it next week; an open link is for a group forming now, and the
 * longer it lives the longer a forwarded copy keeps working.
 */
const LINK_TTL = 7 * 24 * 60 * 60 * 1000;

export interface InviteContext {
  now: string;
  actor: MemberRow;
}

/**
 * Only for a slot nobody has claimed. Handing out a link to an already-claimed
 * member would be an account takeover with extra steps.
 */
export function createInvite(tx: Tx, memberId: string, context: InviteContext, ttl = INVITE_TTL): { invite: Invite; superseded: string[] } {
  requireMeta(tx);
  const member = requireMember(tx, memberId);

  if (member.profileId !== null) refuse("slot_taken", `${member.displayName} has already joined.`);
  if (member.leftAt !== null) refuse("slot_taken", `${member.displayName} has left this group.`);

  /**
   * One live link per slot: reissuing invalidates whatever was sent before, so
   * an old link found in a chat history cannot still be spent.
   */
  const superseded = tx
    .select({ token: schema.invites.token })
    .from(schema.invites)
    .where(and(eq(schema.invites.memberId, memberId), isNull(schema.invites.redeemedAt)))
    .all();
  tx.delete(schema.invites)
    .where(and(eq(schema.invites.memberId, memberId), isNull(schema.invites.redeemedAt)))
    .run();

  const invite: typeof schema.invites.$inferInsert = {
    token: crypto.randomUUID(),
    memberId,
    createdBy: context.actor.id,
    createdAt: context.now,
    expiresAt: new Date(Date.parse(context.now) + Math.min(ttl, MAX_TTL)).toISOString(),
  };
  tx.insert(schema.invites).values(invite).run();

  return { invite: { ...invite, redeemedAt: null, redeemedBy: null }, superseded: superseded.map((row) => row.token) };
}

/**
 * Minting the group's one open link, revoking whatever preceded it.
 *
 * "One live link" is the shape of the table plus the fact that this object
 * does one thing at a time. Anywhere that admits concurrent writers needs a
 * constraint for it, because two members tapping share at the same moment both
 * insert, and the group has two open doors while everybody involved believes
 * there is one.
 */
export function createGroupLink(tx: Tx, context: InviteContext, ttl = LINK_TTL): { link: GroupLink; superseded: string | null } {
  requireMeta(tx);

  const previous = tx.select().from(schema.groupLink).get();
  const seq = nextSeq(tx);

  const link: typeof schema.groupLink.$inferInsert = {
    id: "live",
    token: crypto.randomUUID(),
    createdBy: context.actor.id,
    createdAt: context.now,
    expiresAt: new Date(Date.parse(context.now) + Math.min(ttl, MAX_TTL)).toISOString(),
    revokedAt: null,
  };

  tx.insert(schema.groupLink).values(link).onConflictDoUpdate({ target: schema.groupLink.id, set: link }).run();

  /**
   * Recorded, and that is the argument for the whole feature being acceptable.
   * An open link is the one thing here that lets somebody nobody invited
   * personally walk into a group's finances, and a group that cannot see it
   * exists has no way to decide it should not.
   */
  if (previous && previous.revokedAt === null) {
    append(tx, { seq, now: context.now, actorId: context.actor.id, kind: "link_revoked", subjectId: previous.token, payload: { expiresAt: previous.expiresAt } });
  }
  append(tx, { seq, now: context.now, actorId: context.actor.id, kind: "link_created", subjectId: link.token, payload: { expiresAt: link.expiresAt } });

  /**
   * Any previous token, not only a live one.
   *
   * The row above is `id: 'live'`, overwritten in place, so after this call
   * the object has no memory of the old token at all — a revoked one included.
   * The derived index has to forget exactly what the object has forgotten: a
   * token still routing to a group that can no longer say anything about it is
   * how a dead link comes back as "invalid" rather than as "turned off".
   */
  return { link: { token: link.token, expiresAt: link.expiresAt }, superseded: previous?.token ?? null };
}

/**
 * The group's open link, if it has a usable one.
 *
 * Expiry is applied here rather than reported, which is the difference between
 * this and `peek`. A member asking "is there a link" is asking whether there is
 * one to share, and an expired token is not — whereas somebody holding a URL
 * needs to be told *why* it does not work, which is a different question with a
 * different answer.
 */
export function liveLink(tx: Tx, now: string): GroupLink | null {
  requireMeta(tx);

  const link = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  if (!link || link.expiresAt < now) return null;

  return { token: link.token, expiresAt: link.expiresAt };
}

export function revokeGroupLink(tx: Tx, context: InviteContext): string | null {
  requireMeta(tx);

  const live = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  if (!live) return null;

  const seq = nextSeq(tx);
  tx.update(schema.groupLink).set({ revokedAt: context.now }).where(eq(schema.groupLink.id, "live")).run();
  append(tx, { seq, now: context.now, actorId: context.actor.id, kind: "link_revoked", subjectId: live.token, payload: { expiresAt: live.expiresAt } });

  return live.token;
}

/**
 * What a link is for, without spending it.
 *
 * Deliberately returns only what the link already implies to whoever holds it.
 * A spent or expired token still describes itself, so the screen can say which
 * of those it is rather than showing "invalid link" for three different
 * reasons — and a group's member *names* are not in here, because those are
 * more than the link implies. That is `placeholders`, which needs a session.
 */
export function peek(tx: Tx, token: string, viewer: string | null, now: string): LinkPreview | null {
  const meta = requireMeta(tx);

  const inviterName = (memberId: string) => tx.select({ name: schema.members.displayName }).from(schema.members).where(eq(schema.members.id, memberId)).get()?.name ?? null;

  const memberCount = tx.select({ count: sql<number>`count(*)` }).from(schema.members).where(isNull(schema.members.leftAt)).get()?.count ?? 0;

  const isMember =
    viewer === null
      ? false
      : tx
          .select({ id: schema.members.id })
          .from(schema.members)
          .where(and(eq(schema.members.profileId, viewer), isNull(schema.members.leftAt)))
          .get() !== undefined;

  const shared = { groupId: meta.id, groupName: meta.name, memberCount, isMember };

  const invite = tx.select().from(schema.invites).where(eq(schema.invites.token, token)).get();
  if (invite) {
    const slot = tx.select({ name: schema.members.displayName }).from(schema.members).where(eq(schema.members.id, invite.memberId)).get();
    return {
      ...shared,
      kind: "invite",
      inviterName: inviterName(invite.createdBy),
      memberName: slot?.name ?? null,
      isRedeemed: invite.redeemedAt !== null,
      isExpired: invite.expiresAt < now,
      isRevoked: false,
    };
  }

  const link = tx.select().from(schema.groupLink).where(eq(schema.groupLink.token, token)).get();
  if (link) {
    return {
      ...shared,
      kind: "group_link",
      inviterName: inviterName(link.createdBy),
      memberName: null,
      isRedeemed: false,
      isExpired: link.expiresAt < now,
      isRevoked: link.revokedAt !== null,
    };
  }

  return null;
}

/**
 * The unclaimed places, for somebody deciding whether they are one of them.
 *
 * The case this exists for: Priya makes the group and types in the six people
 * on the trip, then posts one link. Without this, everybody who arrives becomes
 * a seventh, eighth and ninth member beside the placeholder that is already
 * them, and somebody has to clean up twelve rows by hand afterwards.
 *
 * Requires a session, unlike `peek`, and checks that here rather than leaving
 * it to the route. The names of everybody in a group are more than the link
 * implies to whoever holds it, so the rule belongs with the data — a rule the
 * Worker enforces is a rule that is true of one caller rather than of the
 * object.
 *
 * It is called after the arrival has chosen an account rather than before,
 * which they have to do to join in any case, so it costs the flow nothing.
 */
export function placeholders(tx: Tx, token: string, viewer: string | null, now: string): Placeholder[] {
  requireMeta(tx);
  if (viewer === null) refuse("not_member", "Sign in to see who is going spare.");

  const link = tx.select().from(schema.groupLink).where(eq(schema.groupLink.token, token)).get();
  if (!link) refuse("invite_invalid", "This link is not valid.");
  if (link.revokedAt !== null) refuse("invite_spent", "This link has been turned off.");
  if (link.expiresAt < now) refuse("invite_expired", "This link has expired.");

  return tx
    .select({ memberId: schema.members.id, displayName: schema.members.displayName })
    .from(schema.members)
    .where(and(isNull(schema.members.profileId), isNull(schema.members.leftAt)))
    .orderBy(schema.members.displayName)
    .all();
}

/**
 * Walking in.
 *
 * Two ways through, differing by one statement. Claiming a placeholder sets
 * exactly one column on a member row that already has balances and history.
 * Arriving as somebody new inserts one. Never both, and never a second place
 * for one account — two would be two balances for the same human that can
 * never be reconciled.
 */
export function join(tx: Tx, token: string, profileId: string, context: { now: string; memberId?: string | null; displayName?: string | null }): Member {
  requireMeta(tx);

  const mine = tx.select().from(schema.members).where(eq(schema.members.profileId, profileId)).get();
  if (mine) refuse("already_member", "You are already in this group.");

  const invite = tx.select().from(schema.invites).where(eq(schema.invites.token, token)).get();
  if (invite) return redeemInvite(tx, invite, profileId, context.now);

  const link = tx.select().from(schema.groupLink).where(eq(schema.groupLink.token, token)).get();
  if (!link) refuse("invite_invalid", "This invite link is not valid.");
  if (link.revokedAt !== null) refuse("invite_spent", "This invite link has been turned off.");
  if (link.expiresAt < context.now) refuse("invite_expired", "This invite link has expired.");

  if (context.memberId) return claim(tx, context.memberId, profileId, context.now);

  const name = (context.displayName ?? "").trim();
  if (name.length === 0) refuse("malformed", "A name is needed to join this group.");

  const seq = nextSeq(tx);
  const id = crypto.randomUUID();
  tx.insert(schema.members).values({ id, profileId, displayName: name, joinedAt: context.now, updatedAt: context.now, seq }).run();
  append(tx, { seq, now: context.now, actorId: null, kind: "member_joined", subjectId: id, payload: { displayName: name, previousName: null } });

  return requireMember(tx, id);
}

function redeemInvite(tx: Tx, invite: typeof schema.invites.$inferSelect, profileId: string, now: string): Member {
  if (invite.redeemedAt !== null) refuse("invite_spent", "This invite link has already been used.");
  if (invite.expiresAt < now) refuse("invite_expired", "This invite link has expired.");

  const member = claim(tx, invite.memberId, profileId, now);
  tx.update(schema.invites).set({ redeemedAt: now, redeemedBy: profileId }).where(eq(schema.invites.token, invite.token)).run();
  return member;
}

/**
 * The claim itself: one column.
 *
 * `actorId` is null on the event, and that is correct rather than a gap. The
 * feed line is "Priya joined"; there is no third party who did it to her.
 */
function claim(tx: Tx, memberId: string, profileId: string, now: string): Member {
  const member = requireMember(tx, memberId);

  if (member.profileId !== null) refuse("slot_taken", "Someone has already claimed that place.");
  if (member.leftAt !== null) refuse("slot_taken", "That person has left this group.");

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ profileId, updatedAt: now, seq }).where(eq(schema.members.id, memberId)).run();
  append(tx, { seq, now, actorId: null, kind: "member_joined", subjectId: memberId, payload: { displayName: member.displayName, previousName: null } });

  return requireMember(tx, memberId);
}
