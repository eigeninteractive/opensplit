import { eq, sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { counters } from "./schema";

/**
 * Every write to `profiles` goes in one `db.batch` (a transaction) behind
 * `nextProfileVersion`, and sets `version: profileVersion`:
 *
 * ```ts
 * await db.batch([nextProfileVersion(db), db.update(profiles).set({ ...changes, version: profileVersion })]);
 * ```
 */
export function nextProfileVersion(db: DrizzleD1Database) {
  return db
    .insert(counters)
    .values({ name: "profiles", value: 1 })
    .onConflictDoUpdate({ target: counters.name, set: { value: sql`${counters.value} + 1` } });
}

/** The version `nextProfileVersion` just took, read inside the same batch. */
export const profileVersion = sql<number>`(select ${counters.value} from ${counters} where ${eq(counters.name, "profiles")})`;
