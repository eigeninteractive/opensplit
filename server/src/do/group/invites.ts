import { and, eq, isNull, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { GroupLink, Invite, JoinRequest, LinkPreview, Member, Placeholder } from "../../schemas/ledger";
import { append } from "./events";
import { refuse } from "./refusal";
import { type MemberRow, nextSeq, requireMember, requireMeta, type Tx, type WriteContext } from "./store";
import { stageLinkToken, stageMembership } from "./upkeep";

/**
 * Two doors into a group. An invite hands one named placeholder to whoever
 * holds its token; the group link lets anybody holding it join, which is why
 * minting and revoking it are on the record. One `peek` and one `join` serve
 * both, because the person holding a URL cannot know which kind it is.
 */

const DAY = 24 * 60 * 60 * 1000;
const INVITE_TTL = 14 * DAY;
/** Shorter: an open link is for a group forming now, and a forwarded copy keeps working. */
const LINK_TTL = 7 * DAY;

const expiry = (now: string, ttl: number) => new Date(Date.parse(now) + ttl).toISOString();

/** An invite for an unclaimed place. Reissuing invalidates the previous one. */
export function createInvite(tx: Tx, memberId: string, { now, actor }: WriteContext): Invite {
  requireMeta(tx);
  const member = requireMember(tx, memberId);
  if (member.profileId !== null) refuse("slot_taken", `${member.displayName} has already joined.`);
  if (member.leftAt !== null) refuse("slot_taken", `${member.displayName} has left this group.`);

  const unredeemed = and(eq(schema.invites.memberId, memberId), isNull(schema.invites.redeemedAt));
  for (const { token } of tx.select({ token: schema.invites.token }).from(schema.invites).where(unredeemed).all()) {
    stageLinkToken(tx, token, "invite", now, true);
  }
  tx.delete(schema.invites).where(unredeemed).run();

  const invite = { token: crypto.randomUUID(), memberId, createdBy: actor.id, createdAt: now, expiresAt: expiry(now, INVITE_TTL), redeemedAt: null, redeemedBy: null };
  tx.insert(schema.invites).values(invite).run();
  stageLinkToken(tx, invite.token, "invite", now);
  return invite;
}

/** Mints the group's one open link, replacing (and forgetting) whatever preceded it. */
export function createGroupLink(tx: Tx, { now, actor }: WriteContext): GroupLink {
  requireMeta(tx);
  const previous = tx.select().from(schema.groupLink).get();
  const seq = nextSeq(tx);

  const link = { id: "live", token: crypto.randomUUID(), createdBy: actor.id, createdAt: now, expiresAt: expiry(now, LINK_TTL), revokedAt: null };
  tx.insert(schema.groupLink).values(link).onConflictDoUpdate({ target: schema.groupLink.id, set: link }).run();

  const written = { seq, now, actorId: actor.id };
  if (previous && previous.revokedAt === null) {
    append(tx, { ...written, kind: "link_revoked", subjectId: previous.token, link: { expiresAt: previous.expiresAt } });
  }
  append(tx, { ...written, kind: "link_created", subjectId: link.token, link: { expiresAt: link.expiresAt } });

  if (previous) stageLinkToken(tx, previous.token, "group_link", now, true);
  stageLinkToken(tx, link.token, "group_link", now);
  return { token: link.token, expiresAt: link.expiresAt };
}

/** The link a member could share now: expired or revoked is none. */
export function liveLink(tx: Tx, now: string): GroupLink | null {
  const link = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  return link && link.expiresAt >= now ? { token: link.token, expiresAt: link.expiresAt } : null;
}

/**
 * Turns the open link off. D1 keeps routing the token, so a stale URL is told
 * "turned off" rather than "never valid"; minting a new link forgets it.
 */
export function revokeGroupLink(tx: Tx, { now, actor }: WriteContext): string | null {
  const live = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  if (!live) return null;

  const seq = nextSeq(tx);
  tx.update(schema.groupLink).set({ revokedAt: now }).where(eq(schema.groupLink.id, "live")).run();
  append(tx, { seq, now, actorId: actor.id, kind: "link_revoked", subjectId: live.token, link: { expiresAt: live.expiresAt } });
  return live.token;
}

/** What a link is for, without spending it, told to anybody holding it. Member names are not included. */
export function peek(tx: Tx, token: string, viewer: string | null, now: string): LinkPreview | null {
  const meta = requireMeta(tx);
  const nameOf = (memberId: string) => tx.select({ name: schema.members.displayName }).from(schema.members).where(eq(schema.members.id, memberId)).get()?.name ?? null;
  const memberCount = tx.select({ count: sql<number>`count(*)` }).from(schema.members).where(isNull(schema.members.leftAt)).get()?.count ?? 0;
  const isMember = viewer !== null && activeMemberFor(tx, viewer) !== undefined;
  const shared = { groupId: meta.id, groupName: meta.name, memberCount, isMember };

  const invite = tx.select().from(schema.invites).where(eq(schema.invites.token, token)).get();
  if (invite) {
    return {
      ...shared,
      kind: "invite",
      inviterName: nameOf(invite.createdBy),
      memberName: nameOf(invite.memberId),
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
      inviterName: nameOf(link.createdBy),
      memberName: null,
      isRedeemed: false,
      isExpired: link.expiresAt < now,
      isRevoked: link.revokedAt !== null,
    };
  }
  return null;
}

/** The unclaimed places behind an open link. Other people's names, so a session is required. */
export function placeholders(tx: Tx, token: string, now: string): Placeholder[] {
  requireMeta(tx);
  requireLiveLink(tx, token, now);
  return tx
    .select({ id: schema.members.id, displayName: schema.members.displayName })
    .from(schema.members)
    .where(and(isNull(schema.members.profileId), isNull(schema.members.leftAt)))
    .orderBy(schema.members.displayName)
    .all();
}

/**
 * Walking in: redeem an invite, claim a placeholder behind an open link, or
 * arrive as somebody new. Never a second place for one account.
 */
export function join(tx: Tx, token: string, profileId: string, request: JoinRequest, now: string): Member {
  requireMeta(tx);
  if (tx.select().from(schema.members).where(eq(schema.members.profileId, profileId)).get()) {
    refuse("already_member", "You are already in this group.");
  }

  const invite = tx.select().from(schema.invites).where(eq(schema.invites.token, token)).get();
  if (invite) {
    if (invite.redeemedAt !== null) refuse("invite_spent", "This invite link has already been used.");
    if (invite.expiresAt < now) refuse("invite_expired", "This invite link has expired.");
    tx.update(schema.invites).set({ redeemedAt: now, redeemedBy: profileId }).where(eq(schema.invites.token, token)).run();
    return claim(tx, invite.memberId, profileId, now);
  }

  requireLiveLink(tx, token, now);
  if (request.memberId !== null) return claim(tx, request.memberId, profileId, now);

  const name = request.displayName?.trim() ?? "";
  if (name.length === 0) refuse("malformed", "A name is needed to join this group.");

  const seq = nextSeq(tx);
  const id = crypto.randomUUID();
  tx.insert(schema.members).values({ id, profileId, displayName: name, joinedAt: now, updatedAt: now, seq }).run();
  append(tx, { seq, now, actorId: null, kind: "member_joined", subjectId: id, member: { displayName: name, previousName: null } });
  stageMembership(tx, profileId, null, now);
  return requireMember(tx, id);
}

/** Taking over a placeholder sets one column; no balance moves. Nobody did it to them, so no actor. */
function claim(tx: Tx, memberId: string, profileId: string, now: string): Member {
  const member = requireMember(tx, memberId);
  if (member.profileId !== null) refuse("slot_taken", "Someone has already claimed that place.");
  if (member.leftAt !== null) refuse("slot_taken", "That person has left this group.");

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ profileId, updatedAt: now, seq }).where(eq(schema.members.id, memberId)).run();
  append(tx, { seq, now, actorId: null, kind: "member_joined", subjectId: memberId, member: { displayName: member.displayName, previousName: null } });
  stageMembership(tx, profileId, null, now);
  return requireMember(tx, memberId);
}

function requireLiveLink(tx: Tx, token: string, now: string): void {
  const link = tx.select().from(schema.groupLink).where(eq(schema.groupLink.token, token)).get();
  if (!link) refuse("invite_invalid", "This invite link is not valid.");
  if (link.revokedAt !== null) refuse("invite_spent", "This invite link has been turned off.");
  if (link.expiresAt < now) refuse("invite_expired", "This invite link has expired.");
}

function activeMemberFor(tx: Tx, profileId: string): MemberRow | undefined {
  return tx
    .select()
    .from(schema.members)
    .where(and(eq(schema.members.profileId, profileId), isNull(schema.members.leftAt)))
    .get();
}
