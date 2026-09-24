import { index, integer, primaryKey, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

/**
 * What the rate object holds.
 *
 * One Durable Object for the whole deployment, reached with
 * `getByName("global")`. It is the only writer of the KV month blobs, and that
 * is the reason it exists at all: KV is last-write-wins, so a daily cron run
 * overlapping an on-demand backfill would rebuild the same month from two
 * readers and silently drop whichever rate landed first. Serializing writers is
 * what this primitive is for.
 *
 * None of this is in D1. Rates are not per-account, nothing joins them to
 * anything, and every device reads them from KV rather than from a query — so
 * putting them in the relational database would buy a JOIN nobody performs.
 */

/**
 * The rate history, one row per currency per publication date.
 *
 * Immutable once written: a rate for a past date does not change. That is what
 * lets the client keep a high-water mark instead of a cursor, and why the
 * upsert below is `onConflictDoNothing` rather than a replace — a second
 * provider answering for a day we already covered must not overwrite the
 * answer the first one gave, or the `source` stamped on somebody's expense
 * stops matching the rate it was converted with.
 */
export const fxRates = sqliteTable(
  "fx_rates",
  {
    /** `YYYY-MM-DD`. Text because it is a date, and because ISO dates sort. */
    asOf: text("as_of").notNull(),
    currency: text("currency").notNull(),

    /** Units of `currency` per one USD. USD itself is stored as exactly 1. */
    rate: real("rate").notNull(),

    /** Which provider supplied it. See the waterfall in `fx/providers.ts`. */
    source: text("source").notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.asOf, table.currency] }),
    // The republish reads a month at a time, which is a range over `as_of`
    // alone; the primary key leads with it, so the scan is already covered.
    index("fx_rates_currency").on(table.currency, table.asOf),
  ],
);

/**
 * Why a currency is missing, when one is.
 *
 * The one thing worth keeping from the `fx_providers` table this replaces. The
 * rest of that table — priority, enabled, config — became an ordered array in
 * code, because there was never an interface to edit it with and every change
 * was a deploy anyway. This is not configuration; it is the answer to a
 * question that is otherwise unanswerable from outside.
 */
export const providerHealth = sqliteTable("provider_health", {
  name: text("name").primaryKey(),
  lastAttemptAt: text("last_attempt_at"),
  lastSuccessAt: text("last_success_at"),

  /** Null after a success, so a stale error cannot linger and mislead. */
  lastError: text("last_error"),
});

/**
 * Backfills already asked for, so the same day is not chased repeatedly.
 *
 * A device records an expense backdated past what the server holds and says so;
 * so does every other device in that group, within the same second, because
 * they all sync the same entry. Without this, one backdated dinner in a group
 * of six is six provider requests against a 1,500-a-month free tier.
 *
 * Keyed on the day rather than on the day and currency: a run fills every
 * missing currency for that date at once, so a second request naming a
 * different currency is asking for work already done.
 */
export const backfillRequests = sqliteTable("backfill_requests", {
  /** `YYYY-MM-DD`. */
  asOf: text("as_of").primaryKey(),

  /** Epoch millis of the last attempt. See `BACKFILL_COOLDOWN`. */
  attemptedAt: integer("attempted_at").notNull(),

  /**
   * How many times this date has been chased.
   *
   * A date no provider will ever answer for — a public holiday before a
   * provider's history begins, a currency none of them carry — would otherwise
   * be retried by every device, forever. After a handful of attempts it is
   * accepted as unanswerable.
   */
  attempts: integer("attempts").notNull().default(1),
});
