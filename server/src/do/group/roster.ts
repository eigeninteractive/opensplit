import { eq, isNotNull, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Group, GroupCreate, GroupPatch, Member, MemberCreate, MemberPatch } from "../../schemas/ledger";
import { isSettled } from "./balances";
import { append } from "./events";
import { refuse } from "./refusal";
import { findMeta, type MemberRow, type MetaRow, nextSeq, requireMember, requireMeta, type Tx } from "./store";

/**
 * The group and the people in it.
 *
 * Membership is the only question this object ever asks. There is deliberately
 * no owner, no admin and no rank: a shared ledger is something a group of
 * friends keeps between them, and every power a role was gating turned out to
 * be either destructive enough that nobody should hold it over somebody else,
 * or harmless enough that everybody should. Removing the rank also removed a
 * whole class of problem rather than solving it — an owner who left, or
 * deleted their account, stranded a group nobody could then administer.
 *
 * What is left is one predicate, applied evenly, plus the column rules below.
 * Those are the awkward half: "you may change this column, but only on your
 * own row" needs both the old and the new values to decide, and most places
 * that gate writes can see only one. Here both are in hand, so a refusal can
 * say what it refused.
 */

export interface WriteContext {
  now: string;
  actor: MemberRow;
}

export interface RosterWrite<T> {
  value: T;
  changed: boolean;
}

export function readGroup(meta: MetaRow): Group {
  return meta;
}

/**
 * Creating the group, and its first member, in one statement each.
 *
 * Both in one call, because that is what removes the bootstrap problem:
 * gating member writes on membership is unsatisfiable for the first member,
 * since you become a member by making the very row the rule would refuse.
 *
 * Any escape hatch for that case — "the creator may also write members" — is
 * an authorization in disguise, and one that can be re-entered: write yourself
 * or a stranger in, seize the group, leave, rejoin. A call that writes both
 * rows at once has no window to escape from, which is what lets `createdBy`
 * stay a description of who made this rather than a permission.
 */
export function createGroup(tx: Tx, input: GroupCreate, profileId: string, context: { now: string }): RosterWrite<Group> {
  const existing = findMeta(tx);

  if (existing) {
    /**
     * A retry whose response was lost. Idempotent for the account that made
     * the group, and a refusal for anybody else — an id somebody else is
     * already using is not an id you get to claim, even though you chose it.
     */
    const creator = tx.select().from(schema.members).where(eq(schema.members.id, existing.createdBy)).get();
    if (creator?.profileId === profileId) return { value: readGroup(existing), changed: false };
    refuse("group_exists", "A group already exists here.");
  }

  const seq = nextSeq(tx);

  tx.insert(schema.members)
    .values({
      id: input.memberId,
      profileId,
      displayName: input.displayName,
      joinedAt: context.now,
      updatedAt: context.now,
      seq,
    })
    .run();

  const meta: typeof schema.meta.$inferInsert = {
    id: input.id,
    name: input.name,
    defaultCurrency: input.defaultCurrency,
    isDirect: input.isDirect,
    simplifyDebts: input.simplifyDebts,
    createdBy: input.memberId,
    createdAt: context.now,
    updatedAt: context.now,
    seq,
  };
  tx.insert(schema.meta).values(meta).run();

  /**
   * No event. "Ravi joined Ravi's flat" is not news, and it would open every
   * feed in the app with a line nobody needs.
   */
  return { value: readGroup(requireMeta(tx)), changed: true };
}

/**
 * Renaming, archiving and the two settings.
 *
 * Any member may do all of it. None of it touches money, all of it is
 * reversible by anybody who disagrees, and all of it is visible — which is the
 * test for whether something needs a rank behind it.
 */
export function updateGroup(tx: Tx, patch: GroupPatch, context: WriteContext): RosterWrite<Group> {
  const meta = requireMeta(tx);

  const name = patch.name ?? meta.name;
  const simplifyDebts = patch.simplifyDebts ?? meta.simplifyDebts;
  const archivedAt = patch.archivedAt === undefined ? meta.archivedAt : patch.archivedAt;

  if (name === meta.name && simplifyDebts === meta.simplifyDebts && archivedAt === meta.archivedAt) {
    return { value: readGroup(meta), changed: false };
  }

  const seq = nextSeq(tx);
  tx.update(schema.meta).set({ name, simplifyDebts, archivedAt, updatedAt: context.now, seq }).where(eq(schema.meta.id, meta.id)).run();

  /**
   * One event per thing that actually happened, rather than the first one
   * that matched. An `if/elsif` chain records exactly one, so a patch that
   * renames and archives in the same call reports the rename and drops the
   * archive on the floor. Nothing in the app sends both at once, but a record
   * whose completeness depends on that is not a record.
   */
  const shared = { seq, now: context.now, actorId: context.actor.id };

  if (name !== meta.name) {
    // The old name as well, because a rename is the one change whose meaning
    // is entirely in what it was before.
    append(tx, { ...shared, kind: "group_renamed", payload: { name, previousName: meta.name } });
  }
  if (archivedAt !== null && meta.archivedAt === null) {
    append(tx, { ...shared, kind: "group_archived", payload: { name, previousName: null } });
  }
  if (archivedAt === null && meta.archivedAt !== null) {
    append(tx, { ...shared, kind: "group_restored", payload: { name, previousName: null } });
  }

  return { value: readGroup(requireMeta(tx)), changed: true };
}

/**
 * Adding somebody who has never opened the app.
 *
 * A placeholder is a full member: they can pay, hold a balance and be settled
 * with. That is the decision the whole schema rests on — had financial rows
 * referenced accounts, every person joining a group would be a data migration.
 */
export function addMember(tx: Tx, input: MemberCreate, context: WriteContext): RosterWrite<Member> {
  requireMeta(tx);

  const existing = tx.select().from(schema.members).where(eq(schema.members.id, input.id)).get();
  if (existing) return { value: existing, changed: false };

  const seq = nextSeq(tx);
  tx.insert(schema.members)
    .values({
      id: input.id,
      profileId: null,
      displayName: input.displayName,
      upiVpa: input.upiVpa,
      joinedAt: context.now,
      updatedAt: context.now,
      seq,
    })
    .run();

  append(tx, { seq, now: context.now, actorId: context.actor.id, kind: "member_added", subjectId: input.id, payload: { displayName: input.displayName, previousName: null } });

  return { value: requireMember(tx, input.id), changed: true };
}

/**
 * The column rules, which are most of what this file is for.
 *
 * Each one closes something a single unguarded update would otherwise allow.
 * Deciding access a row at a time — "you are in this group, so you may write
 * this group's member rows" — admits all of them:
 *
 *   - rewrite somebody else's `upiVpa`, so the settle-up handoff pays you;
 *   - rename another account holder;
 *   - set `leftAt` on somebody still owed money, cutting them out of the group
 *     and off from reading it.
 *
 * There is no exemption for whoever created the group, and the first of those
 * is why. Rewriting another member's payment handle is the one power here that
 * can redirect real money. Nobody needs it, so nobody has it.
 */
export function updateMember(tx: Tx, memberId: string, patch: MemberPatch, context: WriteContext): RosterWrite<Member> {
  requireMeta(tx);
  const target = requireMember(tx, memberId);

  /**
   * Whose descriptive fields you may edit: your own, and any placeholder.
   * Placeholders are deliberately open — somebody has to be able to name and
   * pay a person who has never opened the app, which is the entire point of
   * them existing.
   */
  const mineOrPlaceholder = target.profileId === null || target.id === context.actor.id;

  const displayName = patch.displayName ?? target.displayName;
  const upiVpa = patch.upiVpa === undefined ? target.upiVpa : patch.upiVpa;
  const leftAt = patch.leftAt === undefined ? target.leftAt : patch.leftAt;

  if ((displayName !== target.displayName || upiVpa !== target.upiVpa) && !mineOrPlaceholder) {
    refuse("forbidden", `Only ${target.displayName} can change their own name or payment handle.`);
  }

  /**
   * Leaving is always yours to do, settled or not: a debt is not a reason
   * somebody can be held in a group, and the app says plainly that leaving
   * does not clear one.
   *
   * Removing somebody else is different, because it is not only a removal —
   * membership is what lets you read the group, so it also cuts them off, and
   * the person most worth cutting off is exactly the one still owed money, or
   * the one still chasing you for it. Requiring a zero balance in every
   * currency makes removal a piece of tidying up rather than a way to walk
   * away from a debt or to hide from one.
   */
  if (leftAt !== target.leftAt && target.id !== context.actor.id && !isSettled(tx, target.id)) {
    refuse("not_settled", `${target.displayName} is not settled up in this group, so they cannot be removed from it.`);
  }

  if (displayName === target.displayName && upiVpa === target.upiVpa && leftAt === target.leftAt) {
    return { value: target, changed: false };
  }

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ displayName, upiVpa, leftAt, updatedAt: context.now, seq }).where(eq(schema.members.id, memberId)).run();

  const shared = { seq, now: context.now, actorId: context.actor.id, subjectId: memberId };

  if (leftAt !== null && target.leftAt === null) {
    append(tx, { ...shared, kind: "member_left", payload: { displayName, previousName: null } });
  }
  if (displayName !== target.displayName) {
    append(tx, { ...shared, kind: "member_renamed", payload: { displayName, previousName: target.displayName } });
  }

  /**
   * A payment handle and a rejoin are deliberately silent. A handle is
   * personal bookkeeping, and there is no kind for coming back — the client's
   * enum has never had one, and inventing a word the app cannot render would
   * put a blank line in the feed rather than a sentence.
   */
  return { value: requireMember(tx, memberId), changed: true };
}

/**
 * Deleting an account, as this group experiences it.
 *
 * It does **not** remove other people's ledgers. Money you paid, money you owe
 * and the settlements between you are facts about their group as much as
 * yours, and erasing your side would leave everybody else's balances wrong
 * with nothing to explain it. What happens instead is the thing the schema was
 * built for: the member row keeps its name and loses its account, which is
 * exactly the state of somebody a friend added who never signed up.
 *
 * A group where you were the only account holder is different. Nobody left can
 * ever read it again, so holding your expense descriptions forever in a group
 * with no living reader is the opposite of what was asked for. Those are
 * collected outright, and this object can decide that by itself, because the
 * question — is anybody left here with an account — is one scan of a table it
 * already holds.
 */
export function forgetProfile(tx: Tx, profileId: string, context: { now: string }): { forgotten: boolean; purged: boolean } {
  const meta = findMeta(tx);
  if (!meta) return { forgotten: false, purged: false };

  const member = tx.select().from(schema.members).where(eq(schema.members.profileId, profileId)).get();
  if (!member) return { forgotten: false, purged: false };

  const others = tx.select({ count: sql<number>`count(*)` }).from(schema.members).where(sql`${schema.members.profileId} is not null and ${schema.members.profileId} <> ${profileId}`).get();

  if ((others?.count ?? 0) === 0) {
    purge(tx, context.now);
    return { forgotten: true, purged: true };
  }

  const seq = nextSeq(tx);
  tx.update(schema.members).set({ profileId: null, updatedAt: context.now, seq }).where(eq(schema.members.id, member.id)).run();

  return { forgotten: true, purged: false };
}

/** Whether anybody here could still read this group. */
export function hasAccountHolders(tx: Tx): boolean {
  const row = tx.select({ count: sql<number>`count(*)` }).from(schema.members).where(isNotNull(schema.members.profileId)).get();
  return (row?.count ?? 0) > 0;
}

/**
 * Collecting the group.
 *
 * The one operation here that destroys somebody's data, so what goes is
 * written out in order rather than left to a cascade: the children before the
 * entries that own them, the record and the invites before the members they
 * attribute things to, and `meta` last because it names the member who created
 * it. Naming the order is also the honest way to write this — what goes, and
 * in what sequence, is legible rather than emergent.
 *
 * What is left is one row in `tombstone`, which is how the change feed tells
 * every device that still holds a copy.
 */
export function purge(tx: Tx, now: string): void {
  const seq = nextSeq(tx);
  const groupId = requireMeta(tx).id;

  tx.delete(schema.entryPayers).run();
  tx.delete(schema.entryShares).run();
  tx.delete(schema.entries).run();
  tx.delete(schema.events).run();
  tx.delete(schema.invites).run();
  tx.delete(schema.groupLink).run();
  tx.delete(schema.meta).run();
  tx.delete(schema.members).run();

  tx.insert(schema.tombstone).values({ id: "purged", groupId, purgedAt: now, seq }).onConflictDoNothing().run();
}
