import { and, eq, isNotNull, ne } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Group, GroupInput, Member, MemberInput } from "../../schemas/ledger";
import { isSettled } from "./balances";
import { append } from "./events";
import { refuse } from "./refusal";
import { findMemberByProfile, findMeta, nextSeq, purge, requireMember, requireMeta, type Tx, type WriteContext } from "./store";
import { stageMembership, stagePurge, touchDormancy } from "./upkeep";

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
      createdBy: input.creatorId,
      createdAt: now,
      updatedAt: now,
      seq,
    })
    .run();

  stageMembership(tx, profileId, null, now);
  touchDormancy(tx, now);
  return requireMeta(tx);
}

/** Rename, archive or restore, and settings. Any member; all of it is visible and reversible. */
export function updateGroup(tx: Tx, input: GroupInput, { now, actor }: WriteContext): Group {
  const meta = requireMeta(tx);
  const { name, simplifyDebts, archivedAt } = input;
  if (name === meta.name && simplifyDebts === meta.simplifyDebts && archivedAt === meta.archivedAt) return meta;

  const seq = nextSeq(tx);
  tx.update(schema.meta).set({ name, simplifyDebts, archivedAt, updatedAt: now, seq }).where(eq(schema.meta.id, meta.id)).run();

  const written = { seq, now, actorId: actor.id };
  if (name !== meta.name) append(tx, { ...written, kind: "group_renamed", group: { name, previousName: meta.name } });
  if (archivedAt !== null && meta.archivedAt === null) append(tx, { ...written, kind: "group_archived", group: { name, previousName: null } });
  if (archivedAt === null && meta.archivedAt !== null) append(tx, { ...written, kind: "group_restored", group: { name, previousName: null } });

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
 * money. Leaving is always yours; removing somebody else requires them settled.
 */
function updateMember(tx: Tx, memberId: string, input: MemberInput, { now, actor }: WriteContext): Member {
  const target = requireMember(tx, memberId);
  const { displayName, upiVpa, leftAt } = input;

  const mineOrPlaceholder = target.profileId === null || target.id === actor.id;
  if ((displayName !== target.displayName || upiVpa !== target.upiVpa) && !mineOrPlaceholder) {
    refuse("forbidden", `Only ${target.displayName} can change their own name or payment handle.`);
  }
  if (leftAt !== target.leftAt && target.id !== actor.id && !isSettled(tx, target.id)) {
    refuse("not_settled", `${target.displayName} is not settled up in this group, so they cannot be removed from it.`);
  }
  if (displayName === target.displayName && upiVpa === target.upiVpa && leftAt === target.leftAt) return target;

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ displayName, upiVpa, leftAt, updatedAt: now, seq }).where(eq(schema.members.id, memberId)).run();

  // A payment handle and a rejoin are deliberately silent.
  const written = { seq, now, actorId: actor.id, subjectId: memberId };
  if (leftAt !== null && target.leftAt === null) append(tx, { ...written, kind: "member_left", member: { displayName, previousName: null } });
  if (displayName !== target.displayName) append(tx, { ...written, kind: "member_renamed", member: { displayName, previousName: target.displayName } });

  if (target.profileId !== null) stageMembership(tx, target.profileId, leftAt, now);
  return requireMember(tx, memberId);
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
    .where(and(isNotNull(schema.members.profileId), ne(schema.members.profileId, profileId)))
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
  if (findMemberByProfile(tx, heirId)) return forgetProfile(tx, profileId, null, now);

  tx.update(schema.members)
    .set({ profileId: heirId, updatedAt: now, seq: nextSeq(tx) })
    .where(eq(schema.members.id, member.id))
    .run();
  stageMembership(tx, heirId, member.leftAt, now);
  return { forgotten: true, purged: false };
}
