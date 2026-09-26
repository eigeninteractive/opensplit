import { and, eq, inArray, isNull, lt, notInArray, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";

import { user } from "./auth-schema";
import { memberships, profiles } from "./db/d1/schema";

/** The two crons. Dormant groups are not swept: each group object arms its own alarm. */

export async function refreshRates(env: Env): Promise<void> {
  const outcome = await env.FX.getByName("global").refresh();
  // Logged, not alerted: a missing rate is a missing estimate, never a wrong balance.
  if (outcome.missing.length > 0) console.warn("[fx] uncovered after the waterfall", outcome.missing.join(","));
  console.log("[fx] stored", outcome.stored, "months", outcome.months.join(","));
}

const DAY = 24 * 60 * 60 * 1000;
const GUEST_LIFETIME = 90 * DAY;
const GUEST_BATCH = 500;

/** Guests older than 90 days who never joined a group: nothing to lose, and no way to recover them. */
export async function collectAbandonedGuests(env: Env, now: number = Date.now()): Promise<number> {
  const db = drizzle(env.DB);
  // Ordered, so the two deletes below see the same batch.
  const stale = db
    .select({ id: user.id })
    .from(user)
    .where(and(eq(user.isAnonymous, true), lt(user.createdAt, new Date(now - GUEST_LIFETIME)), notInArray(user.id, db.select({ id: memberships.profileId }).from(memberships))))
    .orderBy(user.id)
    .limit(GUEST_BATCH);

  await db.delete(profiles).where(inArray(profiles.id, stale));
  const collected = await db.delete(user).where(inArray(user.id, stale)).returning({ id: user.id });

  if (collected.length > 0) console.log("[sweep] collected", collected.length, "abandoned guest accounts");
  return collected.length;
}

const RECONCILE_BATCH = 200;

/** Restates a rotating slice of groups from their objects into D1's derived index. */
export async function reconcileIndex(env: Env, now: number = Date.now()): Promise<number> {
  const db = drizzle(env.DB);
  const live = isNull(memberships.leftAt);
  const total =
    (
      await db
        .select({ count: sql<number>`count(distinct ${memberships.groupId})` })
        .from(memberships)
        .where(live)
        .get()
    )?.count ?? 0;
  const batches = Math.max(1, Math.ceil(total / RECONCILE_BATCH));
  const week = Math.floor(now / (7 * DAY));

  const groups = await db
    .selectDistinct({ groupId: memberships.groupId })
    .from(memberships)
    .where(live)
    .orderBy(memberships.groupId)
    .limit(RECONCILE_BATCH)
    .offset((week % batches) * RECONCILE_BATCH)
    .all();

  let staged = 0;
  for (const { groupId } of groups) staged += await env.GROUP.getByName(groupId).reconcile();

  console.log("[sweep] reconciled", groups.length, "groups,", staged, "rows restated");
  return groups.length;
}

export async function weeklySweep(env: Env, now: number = Date.now()): Promise<void> {
  const results = await Promise.allSettled([collectAbandonedGuests(env, now), reconcileIndex(env, now)]);
  for (const result of results) {
    if (result.status === "rejected") console.error("[sweep] failed", result.reason);
  }
}
