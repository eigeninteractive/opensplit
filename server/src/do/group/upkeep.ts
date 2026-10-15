import { eq, inArray, sql } from "drizzle-orm";

import type { LinkKind } from "../../db/d1/schema";
import * as schema from "../../db/group/schema";
import { findMeta, hasActiveAccounts, nowIso, purge, requireMeta, type Tx } from "./store";

/** What the object owes D1 (the outbox) and its own future (the schedule behind its one alarm). */

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

/** Records when the shared ledger last changed. */
export function touchActivity(tx: Tx, now: string): void {
  tx.update(schema.meta).set({ lastActivityAt: now }).run();
}

export interface UpkeepOutcome {
  purged: boolean;
}

/** A group exists while an account participates, regardless of inactivity. */
export function collectUnowned(tx: Tx, now: number): UpkeepOutcome {
  const meta = findMeta(tx);
  if (!meta || hasActiveAccounts(tx)) return { purged: false };
  purge(tx, nowIso(now));
  stagePurge(tx, meta.id, nowIso(now));
  return { purged: true };
}

export function stageMembership(tx: Tx, profileId: string, leftAt: string | null, now: string): void {
  const groupId = requireMeta(tx).id;
  tx.insert(schema.outbox)
    .values({ kind: "membership", payload: { groupId, profileId, leftAt, updatedAt: now }, createdAt: now })
    .run();
}

export function stageLinkToken(tx: Tx, token: string, tokenKind: LinkKind, now: string): void {
  const groupId = requireMeta(tx).id;
  tx.insert(schema.outbox).values({ kind: "link_token", payload: { groupId, token, tokenKind }, createdAt: now }).run();
}

export function stagePurge(tx: Tx, groupId: string, now: string): void {
  tx.insert(schema.outbox).values({ kind: "group_purged", payload: { groupId }, createdAt: now }).run();
}

/** An outbox row with its payload narrowed by `kind`, asserted once where JSON leaves SQLite. */
export type OutboxRow = { id: number; attempts: number; createdAt: string } & ({ kind: "membership"; payload: schema.MembershipWrite } | { kind: "link_token"; payload: schema.LinkTokenWrite } | { kind: "group_purged"; payload: schema.PurgeWrite });

export function pendingOutbox(tx: Tx, limit: number): OutboxRow[] {
  return tx.select().from(schema.outbox).orderBy(schema.outbox.id).limit(limit).all() as OutboxRow[];
}

/** Removes what D1 has taken. An empty outbox owes the alarm nothing, so its retry is dropped too. */
export function clearOutbox(tx: Tx, ids: number[]): void {
  if (ids.length > 0) tx.delete(schema.outbox).where(inArray(schema.outbox.id, ids)).run();
  if (tx.select({ id: schema.outbox.id }).from(schema.outbox).limit(1).get() === undefined) unschedule(tx, "outbox");
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
