import { and, eq, isNotNull, isNull, ne } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Group, GroupInput, Member, MemberInput } from "../../schemas/ledger";
import { isGroupSettled, isSettled } from "./balances";
import { append } from "./events";
import { refuse } from "./refusal";
import { findMemberByProfile, findMeta, nextSeq, purge, requireMember, requireMeta, type Tx, type WriteContext } from "./store";
import { collectUnowned, stageMembership, stagePurge, touchActivity } from "./upkeep";

/**
 * The group and its people. Membership is the only permission: no owner, no
 * admin. What is left are column rules, which need the old and new row.
 */

/** The group and its creator's member row in one change, so no bootstrap window exists. */
export function createGroup(tx: Tx, groupId: string, input: GroupInput, profileId: string, now: string): Group {
  const seq = nextSeq(tx);
  tx.insert(schema.members).values({ id: input.creatorId, profileId, displayName: input.creatorName, joinedAt: now, updatedAt: now, seq }).run();
  tx.insert(schema.meta)
    .values({
      id: groupId,
      name: input.name,
      defaultCurrency: input.defaultCurrency,
      isDirect: input.isDirect,
      simplifyDebts: input.simplifyDebts,
      ...appearanceOf(input),
      createdBy: input.creatorId,
      createdAt: now,
      lastActivityAt: now,
      updatedAt: now,
      seq,
    })
    .run();

  stageMembership(tx, profileId, null, now);
  return requireMeta(tx);
}

/** The columns that only decide how the group looks. */
function appearanceOf(input: GroupInput) {
  const { avatarKind, avatarColor, avatarEmoji, avatarIcon, avatarPhoto, coverKind, coverPhoto } = input;
  return { avatarKind, avatarColor, avatarEmoji, avatarIcon, avatarPhoto, coverKind, coverPhoto };
}

/**
 * Shared settings and appearance. Any active member; all of
 * it is visible and reversible. A new look is not an event: the activity feed
 * records what happened to the money and the people, and a picture is neither.
 */
export function updateGroup(tx: Tx, input: GroupInput, { now, actor }: WriteContext): Group {
  const meta = requireMeta(tx);
  const { name, simplifyDebts } = input;
  const appearance = appearanceOf(input);
  const unchanged = name === meta.name && simplifyDebts === meta.simplifyDebts && Object.entries(appearance).every(([column, value]) => meta[column as keyof typeof appearance] === value);
  if (unchanged) return meta;
  if (input.baseSeq !== meta.seq) refuse("stale_base", "This group's settings changed. Refresh them before trying again.");

  const seq = nextSeq(tx);
  tx.update(schema.meta)
    .set({ name, simplifyDebts, ...appearance, updatedAt: now, seq })
    .where(eq(schema.meta.id, meta.id))
    .run();

  const written = { seq, now, actorId: actor.id };
  if (name !== meta.name) append(tx, { ...written, kind: "group_renamed", group: { name, previousName: meta.name } });

  return requireMeta(tx);
}

/** A member row at the id the device minted: a new placeholder, or an edit to one that exists. */
export function putMember(tx: Tx, memberId: string, input: MemberInput, context: WriteContext): Member {
  const existing = tx.select({ id: schema.members.id }).from(schema.members).where(eq(schema.members.id, memberId)).get();
  return existing ? updateMember(tx, memberId, input, context) : addMember(tx, memberId, input, context);
}

/** A placeholder: a full member who has never opened the app. */
function addMember(tx: Tx, memberId: string, input: MemberInput, { now, actor }: WriteContext): Member {
  if (input.leftAt !== null) refuse("malformed", "A new member cannot have left already.");

  const seq = nextSeq(tx);
  tx.insert(schema.members).values({ id: memberId, profileId: null, displayName: input.displayName, upiVpa: input.upiVpa, joinedAt: now, updatedAt: now, seq }).run();
  append(tx, { seq, now, actorId: actor.id, kind: "member_added", subjectId: memberId, member: { displayName: input.displayName, previousName: null } });

  return requireMember(tx, memberId);
}

/**
 * The column rules. Your own row and any placeholder are editable; another
 * account holder's name and payment handle are not, since a handle redirects
 * money. Nobody leaves or is removed owing or owed anything, so a balance is
 * never stranded with somebody who can no longer see the group. A placeholder
 * can be brought back by anybody; an account holder only comes back
 * themselves, with a link.
 */
function updateMember(tx: Tx, memberId: string, input: MemberInput, { now, actor }: WriteContext): Member {
  const target = requireMember(tx, memberId);
  const { displayName, upiVpa } = input;
  // The device says whether; the server's clock says when, once.
  const leftAt = input.leftAt === null ? null : (target.leftAt ?? now);
  const isSelf = target.id === actor.id;
  const leaving = leftAt !== null && target.leftAt === null;
  const returning = leftAt === null && target.leftAt !== null;

  if ((displayName !== target.displayName || upiVpa !== target.upiVpa) && target.profileId !== null && !isSelf) {
    refuse("forbidden", `Only ${target.displayName} can change their own name or payment handle.`);
  }
  if (leaving && !isSettled(tx, target.id)) {
    refuse("not_settled", isSelf ? "You are not settled up in this group yet, so you cannot leave it." : `${target.displayName} is not settled up in this group, so they cannot be removed from it.`);
  }
  if (returning && target.profileId !== null) {
    refuse("forbidden", `${target.displayName} left this group, so only they can come back, with a link.`);
  }
  if (displayName === target.displayName && upiVpa === target.upiVpa && !leaving && !returning) return target;
  if (input.baseSeq !== target.seq) refuse("stale_base", "This member changed. Refresh the group before trying again.");
  if (leaving && target.profileId !== null) {
    const otherActive = tx
      .select({ id: schema.members.id })
      .from(schema.members)
      .where(and(isNotNull(schema.members.profileId), isNull(schema.members.leftAt), ne(schema.members.id, target.id)))
      .limit(1)
      .get();
    if (!otherActive && !isGroupSettled(tx)) refuse("not_settled", "Settle every balance before the last account leaves and deletes this group.");
  }

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ displayName, upiVpa, leftAt, updatedAt: now, seq }).where(eq(schema.members.id, memberId)).run();

  // A payment handle is deliberately silent.
  const written = { seq, now, actorId: actor.id, subjectId: memberId };
  if (leaving) append(tx, { ...written, kind: "member_left", member: { displayName, previousName: null } });
  if (returning) append(tx, { ...written, kind: "member_added", member: { displayName, previousName: null } });
  if (displayName !== target.displayName) append(tx, { ...written, kind: "member_renamed", member: { displayName, previousName: target.displayName } });

  if (target.profileId !== null) stageMembership(tx, target.profileId, leftAt, now);
  const result = requireMember(tx, memberId);
  if (leaving) collectUnowned(tx, Date.parse(now));
  return result;
}

/**
 * An account being deleted. Its member row becomes a placeholder under the
 * name the account last had, keeping everybody else's balances; a group with
 * no other account holder is collected.
 */
export function forgetProfile(tx: Tx, profileId: string, displayName: string | null, now: string): { forgotten: boolean; purged: boolean } {
  const meta = findMeta(tx);
  const member = meta && findMemberByProfile(tx, profileId);
  if (!meta || !member) return { forgotten: false, purged: false };

  const others = tx
    .select({ id: schema.members.id })
    .from(schema.members)
    .where(and(isNotNull(schema.members.profileId), isNull(schema.members.leftAt), ne(schema.members.profileId, profileId)))
    .limit(1)
    .get();

  if (!others) {
    purge(tx, now);
    stagePurge(tx, meta.id, now);
    return { forgotten: true, purged: true };
  }

  tx.update(schema.members)
    .set({ profileId: null, displayName: displayName ?? member.displayName, updatedAt: now, seq: nextSeq(tx) })
    .where(eq(schema.members.id, member.id))
    .run();
  touchActivity(tx, now);
  return { forgotten: true, purged: false };
}

/**
 * A guest signing in to an account they already had: the guest's place in
 * this group becomes that account's, balances and all, since both are the same
 * person. Where that account already holds a place here, the two cannot
 * become one row, so the guest's is left as a placeholder under its name.
 */
export function handOver(tx: Tx, profileId: string, heirId: string, now: string): { forgotten: boolean; purged: boolean } {
  const meta = findMeta(tx);
  const member = meta && findMemberByProfile(tx, profileId);
  if (!meta || !member) return { forgotten: false, purged: false };
  const heir = findMemberByProfile(tx, heirId);
  if (heir) {
    // Signing in transfers an active guest's access to the same person's account.
    if (member.leftAt === null && heir.leftAt !== null) {
      const seq = nextSeq(tx);
      tx.update(schema.members).set({ leftAt: null, updatedAt: now, seq }).where(eq(schema.members.id, heir.id)).run();
      append(tx, { seq, now, actorId: null, kind: "member_joined", subjectId: heir.id, member: { displayName: heir.displayName, previousName: null } });
      stageMembership(tx, heirId, null, now);
    }
    return forgetProfile(tx, profileId, null, now);
  }

  tx.update(schema.members)
    .set({ profileId: heirId, updatedAt: now, seq: nextSeq(tx) })
    .where(eq(schema.members.id, member.id))
    .run();
  stageMembership(tx, heirId, member.leftAt, now);
  touchActivity(tx, now);
  return { forgotten: true, purged: false };
}
