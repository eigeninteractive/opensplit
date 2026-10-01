import { and, eq, gte, inArray, lt, notExists, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";

import { session, user } from "./auth-schema";
import { chunked } from "./chunked";
import { memberships, profiles } from "./db/d1/schema";
import { finishDeletions } from "./forget";

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

/**
 * Guests over 90 days old who are in no group and have not used a session in
 * 90 days: nothing to lose, and no way to recover them. One statement decides
 * and deletes, so a group joined in between cannot be missed; a membership
 * that reaches D1 afterwards is refused, and its group forgets the guest.
 */
export async function collectAbandonedGuests(env: Env, now: number = Date.now()): Promise<number> {
  const db = drizzle(env.DB);
  const cutoff = new Date(now - GUEST_LIFETIME);
  const stale = db
    .select({ id: user.id })
    .from(user)
    .where(
      and(
        eq(user.isAnonymous, true),
        lt(user.createdAt, cutoff),
        notExists(db.select({ one: sql`1` }).from(memberships).where(eq(memberships.profileId, user.id))),
        notExists(
          db
            .select({ one: sql`1` })
            .from(session)
            .where(and(eq(session.userId, user.id), gte(session.updatedAt, cutoff))),
        ),
      ),
    )
    .limit(GUEST_BATCH);

  const collected = await db.delete(user).where(inArray(user.id, stale)).returning({ id: user.id });
  for (const ids of chunked(collected.map((row) => row.id))) await db.delete(profiles).where(inArray(profiles.id, ids));

  if (collected.length > 0) console.log("[sweep] collected", collected.length, "abandoned guest accounts");
  return collected.length;
}

export async function housekeeping(env: Env, now: number = Date.now()): Promise<void> {
  const results = await Promise.allSettled([collectAbandonedGuests(env, now), finishDeletions(env)]);
  for (const result of results) {
    if (result.status === "rejected") console.error("[sweep] failed", result.reason);
  }
}
