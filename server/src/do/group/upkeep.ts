import { eq, inArray, isNull, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import { isGroupSettled } from "./balances";
import { hasAccountHolders, purge } from "./roster";
import { findMeta, nextSeq, type Tx } from "./store";

/**
 * What this object owes D1, and what it owes its own future.
 *
 * Both are here because the alarm is the single consumer of both: a Durable
 * Object has exactly one, and three things want it.
 */

const DAY = 24 * 60 * 60 * 1000;

/**
 * When a quiet group is put away, and when it is finally collected.
 *
 * Archiving is reversible and non-destructive — it sets a flag, and adding an
 * expense clears it — so being wrong about a group costs the people in it
 * nothing. Collecting is not, which is why it takes four times as long and
 * why it refuses a group where anybody still owes anything. A dormant group is
 * not necessarily a finished one, and the most likely reason one goes quiet
 * with a balance outstanding is that the debt is disputed or forgotten, which
 * is exactly when erasing the record is worst.
 */
export const DORMANCY = {
  archiveAfter: 90 * DAY,
  purgeAfter: 365 * DAY,
  /** How long to wait before asking again about a group that is not settled. */
  recheck: 30 * DAY,
} as const;

/** Backoff for a D1 flush that did not land. Capped, not unbounded. */
const RETRY_BACKOFF = [30_000, 2 * 60_000, 10 * 60_000, 60 * 60_000] as const;

type Chore = "outbox" | "archive" | "purge";

export function scheduleAt(tx: Tx, name: Chore, at: number): void {
  tx.insert(schema.schedule)
    .values({ name, dueAt: at })
    .onConflictDoUpdate({ target: schema.schedule.name, set: { dueAt: at } })
    .run();
}

export function unschedule(tx: Tx, name: Chore): void {
  tx.delete(schema.schedule).where(eq(schema.schedule.name, name)).run();
}

/** The earliest thing owed, or null when nothing is. */
export function nextDue(tx: Tx): number | null {
  const row = tx
    .select({ at: sql<number | null>`min(${schema.schedule.dueAt})` })
    .from(schema.schedule)
    .get();
  return row?.at ?? null;
}

export function isDue(tx: Tx, name: Chore, now: number): boolean {
  const row = tx.select({ dueAt: schema.schedule.dueAt }).from(schema.schedule).where(eq(schema.schedule.name, name)).get();
  return row !== undefined && row.dueAt <= now;
}

/**
 * Pushes the dormancy clock out.
 *
 * Called on every ledger write. A group being used is not dormant, and this is
 * the only place that fact is recorded — there is no daily sweep asking every
 * group whether it has been quiet, because an object can schedule itself and a
 * table cannot. A group untouched for three months costs one alarm; under the
 * sweep it cost ninety wake-ups that each found nothing to do.
 */
export function touchDormancy(tx: Tx, now: number): void {
  scheduleAt(tx, "archive", now + DORMANCY.archiveAfter);
  unschedule(tx, "purge");
}

/**
 * When this group was last genuinely used.
 *
 * Recomputed rather than trusted, so the schedule is a hint and this is the
 * truth. An alarm that fired early — because `setAlarm` lost a race with a
 * write, or because a deploy replayed one — finds the group still busy and
 * re-arms instead of putting away something somebody is using.
 */
function lastActivity(tx: Tx): number {
  const row = tx
    .select({ at: sql<string | null>`max(${schema.entries.createdAt})` })
    .from(schema.entries)
    .get();
  const meta = findMeta(tx);
  const latest = row?.at ?? meta?.createdAt;
  return latest ? Date.parse(latest) : Date.now();
}

export interface UpkeepOutcome {
  archived: boolean;
  purged: boolean;
}

/**
 * Archive if quiet, collect if long dead and settled, and re-arm for whatever
 * is next.
 *
 * Public rather than private to `alarm()`, because "bring this group's
 * housekeeping up to date as of this instant" is a real operation: the weekly
 * reconciliation cron calls it, and so does every test that needs to see what
 * happens in three months without waiting.
 */
export function runDormancy(tx: Tx, now: number): UpkeepOutcome {
  const outcome: UpkeepOutcome = { archived: false, purged: false };
  const meta = findMeta(tx);
  if (!meta) return outcome;

  const quietSince = lastActivity(tx);

  if (meta.archivedAt === null) {
    if (quietSince + DORMANCY.archiveAfter > now) {
      scheduleAt(tx, "archive", quietSince + DORMANCY.archiveAfter);
      return outcome;
    }

    /**
     * Archived by nothing and nobody, so the record says so: `actorId` is
     * null, which is the same honest answer it gives for a join. Somebody
     * archiving a group on purpose is a different event with a name on it.
     */
    const seq = nextSeq(tx);
    tx.update(schema.meta)
      .set({ archivedAt: new Date(now).toISOString(), updatedAt: new Date(now).toISOString(), seq })
      .where(eq(schema.meta.id, meta.id))
      .run();
    tx.insert(schema.events)
      .values({ id: crypto.randomUUID(), actorId: null, createdAt: new Date(now).toISOString(), kind: "group_archived", subjectId: null, payload: { name: meta.name, previousName: null }, seq, ordinal: 0 })
      .run();

    outcome.archived = true;
    unschedule(tx, "archive");
  }

  /**
   * A group nobody can read any more is collected as soon as it is quiet,
   * without waiting out the full year: every account holder deleted their
   * account, so there is no device left to be surprised and nobody left whose
   * record this is.
   */
  const unreadable = !hasAccountHolders(tx);
  const due = unreadable ? quietSince : quietSince + DORMANCY.purgeAfter;

  if (due > now) {
    scheduleAt(tx, "purge", due);
    return outcome;
  }

  /**
   * The settled check is the whole safety of this. `outstanding` lists only
   * non-zero positions, so "no rows" is the definition of settled — the same
   * definition removal uses, from the same query, rather than two subtly
   * different ideas of it. A group where money is still owed is simply asked
   * again later, indefinitely.
   */
  if (!isGroupSettled(tx)) {
    scheduleAt(tx, "purge", now + DORMANCY.recheck);
    return outcome;
  }

  purge(tx, new Date(now).toISOString());
  stagePurge(tx, meta.id, new Date(now).toISOString());
  unschedule(tx, "purge");
  unschedule(tx, "archive");
  outcome.purged = true;
  return outcome;
}

/**
 * Writes owed to D1's derived index, staged inside the transaction that caused
 * them.
 *
 * A `fetch` cannot join a `transactionSync`, so an inline D1 write that failed
 * would leave the index behind the object with nothing left to retry it. A row
 * here commits or does not commit with the change itself.
 *
 * The index is allowed to be briefly stale in exactly one direction: a
 * first-pass check that says "no" where the object would say "yes" costs a
 * retry. It can never grant access, because the object re-checks membership
 * itself and is the authority.
 */
export function stageMembership(tx: Tx, groupId: string, profileId: string, leftAt: string | null, now: string): void {
  tx.insert(schema.outbox)
    .values({ kind: "membership", payload: { groupId, profileId, leftAt, updatedAt: now }, createdAt: now })
    .run();
}

export function stageLinkToken(tx: Tx, groupId: string, token: string, kind: "invite" | "group_link", now: string, revoked = false): void {
  tx.insert(schema.outbox)
    .values({ kind: "link_token", payload: { groupId, token, tokenKind: kind, revoked }, createdAt: now })
    .run();
}

export function stagePurge(tx: Tx, groupId: string, now: string): void {
  tx.insert(schema.outbox).values({ kind: "group_purged", payload: { groupId }, createdAt: now }).run();
}

/**
 * A staged write, with its kind and its payload tied together.
 *
 * Storage can type a column but cannot say "this column's type depends on that
 * one's value", so the pairing is asserted here — once, at the boundary where
 * JSON comes back out of SQLite, rather than by casting at each use. Everything
 * downstream narrows on `kind` and never reaches for a property that might not
 * be there.
 */
export type OutboxRow = { id: number; attempts: number; createdAt: string } & ({ kind: "membership"; payload: schema.MembershipWrite } | { kind: "link_token"; payload: schema.LinkTokenWrite } | { kind: "group_purged"; payload: schema.PurgeWrite });

/** Oldest first, so the index converges in the order the object changed. */
export function pendingOutbox(tx: Tx, limit = 100): OutboxRow[] {
  return tx.select().from(schema.outbox).orderBy(schema.outbox.id).limit(limit).all() as OutboxRow[];
}

export function clearOutbox(tx: Tx, ids: number[]): void {
  if (ids.length === 0) return;
  tx.delete(schema.outbox).where(inArray(schema.outbox.id, ids)).run();
}

/**
 * Records a failed flush and says when to try again.
 *
 * At-least-once is enough because every D1 write these rows describe is an
 * idempotent upsert or delete, so a retry that duplicates a write that already
 * landed changes nothing.
 */
export function backoffOutbox(tx: Tx, ids: number[], now: number): void {
  if (ids.length === 0) return;
  tx.update(schema.outbox)
    .set({ attempts: sql`${schema.outbox.attempts} + 1` })
    .where(inArray(schema.outbox.id, ids))
    .run();

  const worst = tx
    .select({ attempts: sql<number>`max(${schema.outbox.attempts})` })
    .from(schema.outbox)
    .get();
  const step = Math.min(worst?.attempts ?? 1, RETRY_BACKOFF.length) - 1;
  scheduleAt(tx, "outbox", now + (RETRY_BACKOFF[Math.max(step, 0)] ?? 60_000));
}

/**
 * Every membership this object holds, for the weekly reconciliation.
 *
 * The object is the truth and D1 is derived, so the only honest way to check
 * them is to ask the object what it believes and overwrite the index with the
 * answer. Restaged as ordinary outbox rows so there is one flush path rather
 * than two.
 */
export function restageAllMemberships(tx: Tx, now: string): number {
  const meta = findMeta(tx);
  if (!meta) return 0;

  const rows = tx.select({ profileId: schema.members.profileId, leftAt: schema.members.leftAt }).from(schema.members).where(sql`${schema.members.profileId} is not null`).all();

  for (const row of rows) {
    if (row.profileId) stageMembership(tx, meta.id, row.profileId, row.leftAt, now);
  }
  return rows.length;
}

/** Tokens this object still considers live, for the same reconciliation. */
export function restageLiveTokens(tx: Tx, now: string): number {
  const meta = findMeta(tx);
  if (!meta) return 0;

  const open = tx.select({ token: schema.invites.token }).from(schema.invites).where(isNull(schema.invites.redeemedAt)).all();
  for (const invite of open) stageLinkToken(tx, meta.id, invite.token, "invite", now);

  const link = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  if (link) stageLinkToken(tx, meta.id, link.token, "group_link", now);

  return open.length + (link ? 1 : 0);
}
