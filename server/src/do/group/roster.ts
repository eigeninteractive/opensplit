import { and, eq, isNotNull, ne } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Group, GroupCreate, GroupUpdate, Member, MemberCreate, MemberUpdate } from "../../schemas/ledger";
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
export function createGroup(tx: Tx, input: GroupCreate, profileId: string, now: string): Group {
  const existing = findMeta(tx);
  if (existing) {
    // A lost response being retried is idempotent for its creator only.
    const creator = requireMember(tx, existing.createdBy);
    if (creator.profileId === profileId) return existing;
    refuse("group_exists", "A group already exists here.");
  }

  const seq = nextSeq(tx);
  tx.insert(schema.members).values({ id: input.memberId, profileId, displayName: input.displayName, joinedAt: now, updatedAt: now, seq }).run();
  tx.insert(schema.meta)
    .values({
      id: input.id,
      name: input.name,
      defaultCurrency: input.defaultCurrency,
      isDirect: input.isDirect,
      simplifyDebts: input.simplifyDebts,
      createdBy: input.memberId,
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
export function updateGroup(tx: Tx, input: GroupUpdate, { now, actor }: WriteContext): Group {
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

/** A placeholder: a full member who has never opened the app. */
export function addMember(tx: Tx, input: MemberCreate, { now, actor }: WriteContext): Member {
  requireMeta(tx);
  const existing = tx.select().from(schema.members).where(eq(schema.members.id, input.id)).get();
  if (existing) return existing;

  const seq = nextSeq(tx);
  tx.insert(schema.members).values({ id: input.id, profileId: null, displayName: input.displayName, upiVpa: input.upiVpa, joinedAt: now, updatedAt: now, seq }).run();
  append(tx, { seq, now, actorId: actor.id, kind: "member_added", subjectId: input.id, member: { displayName: input.displayName, previousName: null } });

  return requireMember(tx, input.id);
}

/**
 * The column rules. Your own row and any placeholder are editable; another
 * account holder's name and payment handle are not, since a handle redirects
 * money. Leaving is always yours; removing somebody else requires them settled.
 */
export function updateMember(tx: Tx, memberId: string, input: MemberUpdate, { now, actor }: WriteContext): Member {
  requireMeta(tx);
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
 * An account being deleted. Its member row becomes a placeholder, keeping
 * everybody else's balances; a group with no other account holder is collected.
 */
export function forgetProfile(tx: Tx, profileId: string, now: string): { forgotten: boolean; purged: boolean } {
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
    .set({ profileId: null, updatedAt: now, seq: nextSeq(tx) })
    .where(eq(schema.members.id, member.id))
    .run();
  return { forgotten: true, purged: false };
}
