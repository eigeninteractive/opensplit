import { index, integer, primaryKey, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

/**
 * The rate object's database: one singleton Durable Object, the only writer of
 * the KV month blobs, so a daily run and a backfill cannot race.
 */

/** Immutable once written: a second provider never overwrites a stored day. */
export const fxRates = sqliteTable(
  "fx_rates",
  {
    /** `YYYY-MM-DD`. */
    asOf: text("as_of").notNull(),
    currency: text("currency").notNull(),
    /** Units of `currency` per one USD; USD is exactly 1. */
    rate: real("rate").notNull(),
    /** The provider that supplied it. */
    source: text("source").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.asOf, table.currency] }),
    // For "which currencies are covered on or before a day".
    index("fx_rates_currency").on(table.currency, table.asOf),
  ],
);

/** Why a currency is missing, answerable from outside the code. */
export const providerHealth = sqliteTable("provider_health", {
  name: text("name").primaryKey(),
  lastAttemptAt: text("last_attempt_at"),
  lastSuccessAt: text("last_success_at"),
  /** Null after a success. */
  lastError: text("last_error"),
});

/** Backfills already asked for, keyed by day, so every device in a group does not chase the same one. */
export const backfillRequests = sqliteTable("backfill_requests", {
  asOf: text("as_of").primaryKey(),
  /** Epoch millis. */
  attemptedAt: integer("attempted_at").notNull(),
  attempts: integer("attempts").notNull().default(1),
});
