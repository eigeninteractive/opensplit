import { eq, inArray, isNotNull, isNull, sql } from "drizzle-orm";

import type { LinkKind } from "../../db/d1/schema";
import * as schema from "../../db/group/schema";
import { isGroupSettled } from "./balances";
import { append } from "./events";
import { findMeta, hasAccountHolders, nextSeq, nowIso, purge, requireMeta, type Tx } from "./store";

/** What the object owes D1 (the outbox) and its own future (the schedule behind its one alarm). */

const DAY = 24 * 60 * 60 * 1000;

/** Archiving is reversible; collecting waits four times as long and requires everyone settled. */
export const DORMANCY = {
  archiveAfter: 90 * DAY,
  purgeAfter: 365 * DAY,
  /** How long to wait before asking an unsettled dormant group again. */
  recheck: 30 * DAY,
} as const;

const RETRY_BACKOFF = [30_000, 2 * 60_000, 10 * 60_000, 60 * 60_000] as const;

function scheduleAt(tx: Tx, name: schema.Chore, at: number): void {
  tx.insert(schema.schedule)
    .values({ name, dueAt: at })
    .onConflictDoUpdate({ target: schema.schedule.name, set: { dueAt: at } })
    .run();
}

function unschedule(tx: Tx, name: schema.Chore): void {
  tx.delete(schema.schedule).where(eq(schema.schedule.name, name)).run();
}

/** The earliest thing owed, or null when nothing is. */
export function nextDue(tx: Tx): number | null {
  return (
    tx
      .select({ at: sql<number | null>`min(${schema.schedule.dueAt})` })
      .from(schema.schedule)
      .get()?.at ?? null
  );
}

/** Called on every ledger write: a group in use is not dormant. */
export function touchDormancy(tx: Tx, now: string): void {
  scheduleAt(tx, "archive", Date.parse(now) + DORMANCY.archiveAfter);
  unschedule(tx, "purge");
}

/** Last genuine use, recomputed from the ledger so an early alarm cannot archive a busy group. */
function lastActivity(tx: Tx, createdAt: string): number {
  const latest =
    tx
      .select({ at: sql<string | null>`max(${schema.entries.createdAt})` })
      .from(schema.entries)
      .get()?.at ?? createdAt;
  return Date.parse(latest);
}

export interface UpkeepOutcome {
  archived: boolean;
  purged: boolean;
}

/** Archive if quiet, collect if long dead and settled, and re-arm for whatever is next. */
export function runDormancy(tx: Tx, now: number): UpkeepOutcome {
  const outcome: UpkeepOutcome = { archived: false, purged: false };
  const meta = findMeta(tx);
  if (!meta) return outcome;

  const quietSince = lastActivity(tx, meta.createdAt);

  if (meta.archivedAt === null) {
    if (quietSince + DORMANCY.archiveAfter > now) {
      scheduleAt(tx, "archive", quietSince + DORMANCY.archiveAfter);
      return outcome;
    }

    const seq = nextSeq(tx);
    const at = nowIso(now);
    tx.update(schema.meta).set({ archivedAt: at, updatedAt: at, seq }).where(eq(schema.meta.id, meta.id)).run();
    append(tx, { seq, now: at, actorId: null, kind: "group_archived", group: { name: meta.name, previousName: null } });
    outcome.archived = true;
    unschedule(tx, "archive");
  }

  // Nobody left with an account: collect as soon as it is quiet.
  const due = hasAccountHolders(tx) ? quietSince + DORMANCY.purgeAfter : quietSince;
  if (due > now) {
    scheduleAt(tx, "purge", due);
    return outcome;
  }

  if (!isGroupSettled(tx)) {
    scheduleAt(tx, "purge", now + DORMANCY.recheck);
    return outcome;
  }

  purge(tx, nowIso(now));
  stagePurge(tx, meta.id, nowIso(now));
  unschedule(tx, "purge");
  unschedule(tx, "archive");
  outcome.purged = true;
  return outcome;
}

export function stageMembership(tx: Tx, profileId: string, leftAt: string | null, now: string): void {
  const groupId = requireMeta(tx).id;
  tx.insert(schema.outbox)
    .values({ kind: "membership", payload: { groupId, profileId, leftAt, updatedAt: now }, createdAt: now })
    .run();
}

export function stageLinkToken(tx: Tx, token: string, tokenKind: LinkKind, now: string, revoked = false): void {
  const groupId = requireMeta(tx).id;
  tx.insert(schema.outbox).values({ kind: "link_token", payload: { groupId, token, tokenKind, revoked }, createdAt: now }).run();
}

export function stagePurge(tx: Tx, groupId: string, now: string): void {
  tx.insert(schema.outbox).values({ kind: "group_purged", payload: { groupId }, createdAt: now }).run();
}

/** An outbox row with its payload narrowed by `kind`, asserted once where JSON leaves SQLite. */
export type OutboxRow = { id: number; attempts: number; createdAt: string } & ({ kind: "membership"; payload: schema.MembershipWrite } | { kind: "link_token"; payload: schema.LinkTokenWrite } | { kind: "group_purged"; payload: schema.PurgeWrite });

export function pendingOutbox(tx: Tx, limit: number): OutboxRow[] {
  return tx.select().from(schema.outbox).orderBy(schema.outbox.id).limit(limit).all() as OutboxRow[];
}

export function clearOutbox(tx: Tx, ids: number[]): void {
  if (ids.length > 0) tx.delete(schema.outbox).where(inArray(schema.outbox.id, ids)).run();
}

/** Counts a failed flush and schedules the retry. Every staged write is idempotent. */
export function backoffOutbox(tx: Tx, ids: number[], now: number): void {
  if (ids.length === 0) return;
  tx.update(schema.outbox)
    .set({ attempts: sql`${schema.outbox.attempts} + 1` })
    .where(inArray(schema.outbox.id, ids))
    .run();

  const worst =
    tx
      .select({ attempts: sql<number>`max(${schema.outbox.attempts})` })
      .from(schema.outbox)
      .get()?.attempts ?? 1;
  scheduleAt(tx, "outbox", now + (RETRY_BACKOFF[Math.min(worst, RETRY_BACKOFF.length) - 1] ?? RETRY_BACKOFF[0]));
}

/** Restates this object's memberships and live tokens for the weekly reconciliation. */
export function restageIndex(tx: Tx, now: string): number {
  if (!findMeta(tx)) return 0;

  const members = tx.select({ profileId: schema.members.profileId, leftAt: schema.members.leftAt }).from(schema.members).where(isNotNull(schema.members.profileId)).all();
  for (const { profileId, leftAt } of members) if (profileId !== null) stageMembership(tx, profileId, leftAt, now);

  const invites = tx.select({ token: schema.invites.token }).from(schema.invites).where(isNull(schema.invites.redeemedAt)).all();
  for (const { token } of invites) stageLinkToken(tx, token, "invite", now);

  const link = tx.select().from(schema.groupLink).where(isNull(schema.groupLink.revokedAt)).get();
  if (link) stageLinkToken(tx, link.token, "group_link", now);

  return members.length + invites.length + (link ? 1 : 0);
}
