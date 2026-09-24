import { and, eq, inArray, isNull, lt, notInArray, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";

import { user } from "./auth-schema";
import { memberships, profiles } from "./db/d1/schema";

/**
 * The two things that are genuinely global.
 *
 * There used to be a third, `30 4 * * *`, for archiving and collecting dormant
 * groups. It is gone: every group sets its own alarm, so each carries its own
 * clock — one wake-up in three months instead of ninety nightly scans that find
 * nothing to do, and no fan-out proportional to the number of groups. What is
 * left here is what no single object can do for itself: rates nobody owns,
 * accounts that belong to no group, and checking that the derived index still
 * agrees with the objects that are the truth.
 */

/** Exchange rates. */
export async function refreshRates(env: Env): Promise<void> {
  const outcome = await env.FX.getByName("global").refresh();

  // Logged rather than alerted. A missing currency is an estimate somebody does
  // not get, never a balance that is wrong, and the provider health table says
  // which source failed and why.
  if (outcome.missing.length > 0) {
    console.warn("[fx] uncovered after the waterfall", outcome.missing.join(","));
  }
  console.log("[fx] stored", outcome.stored, "months", outcome.months.join(","));
}

/**
 * How long a guest account nobody has used survives.
 *
 * A guest is a real account with no way back into it: no email, no Google, one
 * device. Somebody who opened the app, tapped "continue as guest", made no
 * group and never returned has left an account that can never be signed into
 * again and holds nothing. Ninety days is long enough that a real user coming
 * back from a holiday still finds their session, and short enough that the
 * table is not a graveyard.
 */
const GUEST_LIFETIME_DAYS = 90;

/** How many to remove per run, so one week's sweep cannot exhaust a budget. */
const GUEST_BATCH = 500;

/**
 * Guest accounts that belong to no group and nobody has touched.
 *
 * Deliberately conservative on all three counts: anonymous, no membership at
 * all — not even one they have left — and created long ago. A guest with a
 * single group is somebody's ledger and is never collected here; that only
 * happens when they delete the account themselves, or when the group's own
 * dormancy clock runs out.
 *
 * Deleting the `user` row cascades its sessions and linked identities. The
 * `profiles` row goes with it rather than being tombstoned, which is the
 * difference from account deletion: there is no co-member whose history needs
 * a name resolved, because there is no co-member.
 */
export async function collectAbandonedGuests(env: Env, now: number = Date.now()): Promise<number> {
  const db = drizzle(env.DB);
  const cutoff = now - GUEST_LIFETIME_DAYS * 24 * 60 * 60 * 1000;

  const stale = await db
    .select({ id: user.id })
    .from(user)
    .where(and(eq(user.isAnonymous, true), lt(user.createdAt, new Date(cutoff)), notInArray(user.id, db.select({ id: memberships.profileId }).from(memberships))))
    .limit(GUEST_BATCH)
    .all();

  if (stale.length === 0) return 0;

  const ids = stale.map((row) => row.id);
  await db.delete(profiles).where(inArray(profiles.id, ids));
  await db.delete(user).where(inArray(user.id, ids));

  console.log("[sweep] collected", ids.length, "abandoned guest accounts");
  return ids.length;
}

/** How many groups to reconcile per run. A Worker has a subrequest budget. */
const RECONCILE_BATCH = 200;

/**
 * Asks each group's object to restate what it believes into D1.
 *
 * The index is derived and the object is the truth, so reconciling means
 * overwriting the index with the object's answer rather than comparing the two
 * and guessing which is right. It exists because the outbox is at-least-once
 * and a flush that failed every retry would otherwise leave a row wrong
 * forever, with the only symptom being a group missing from somebody's list.
 *
 * Batched, and the batch rotates by group id each week rather than always
 * starting at the same place — a deployment with more groups than the budget
 * would otherwise reconcile the same two hundred forever and never reach the
 * rest.
 */
export async function reconcileIndex(env: Env, now: number = Date.now()): Promise<number> {
  const db = drizzle(env.DB);

  const total = await db
    .select({ count: sql<number>`count(distinct ${memberships.groupId})` })
    .from(memberships)
    .get();
  const groups = await db
    .selectDistinct({ groupId: memberships.groupId })
    .from(memberships)
    .where(isNull(memberships.leftAt))
    .orderBy(memberships.groupId)
    .limit(RECONCILE_BATCH)
    .offset(offsetFor(total?.count ?? 0, now))
    .all();

  let staged = 0;
  for (const { groupId } of groups) {
    staged += await env.GROUP.getByName(groupId).reconcile();
  }

  console.log("[sweep] reconciled", groups.length, "groups,", staged, "rows restated");
  return groups.length;
}

/**
 * Where this week's batch starts.
 *
 * Week number modulo the number of batches, so a deployment larger than one
 * batch works its way around rather than re-checking the same groups forever.
 */
function offsetFor(total: number, now: number): number {
  if (total <= RECONCILE_BATCH) return 0;
  const batches = Math.ceil(total / RECONCILE_BATCH);
  const week = Math.floor(now / (7 * 24 * 60 * 60 * 1000));
  return (week % batches) * RECONCILE_BATCH;
}

/**
 * The weekly sweep, as one call.
 *
 * Both halves run even if the first throws: they are unrelated, and a failure
 * to collect guests must not also stop the index being checked.
 */
export async function weeklySweep(env: Env, now: number = Date.now()): Promise<void> {
  const results = await Promise.allSettled([collectAbandonedGuests(env, now), reconcileIndex(env, now)]);
  for (const result of results) {
    if (result.status === "rejected") console.error("[sweep] failed", result.reason);
  }
}
