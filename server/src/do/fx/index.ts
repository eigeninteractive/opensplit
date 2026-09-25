import { DurableObject } from "cloudflare:workers";
import { and, asc, eq, gte, inArray, lte, sql } from "drizzle-orm";
import { type DrizzleSqliteDODatabase, drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import * as schema from "../../db/fx/schema";
import { type MonthBlob, monthKey } from "../../fx/blob";
import { type FxProvider, providers } from "../../fx/providers";
import { supportedCurrencies } from "../../reference";
import type { FxRate } from "../../schemas/reference";
import migrations from "./migrations/migrations";

/**
 * The only writer of exchange rates.
 *
 * A singleton, reached with `getByName("global")`. It holds the rate history in
 * its own SQLite and publishes one blob per month to KV, where every device
 * reads it.
 *
 * ## Why a singleton object rather than a scheduled function
 *
 * KV is last-write-wins. The daily cron rebuilds a month's blob; so does an
 * on-demand backfill for a backdated expense; and the two overlap on the first
 * of the month with a person in a different timezone. Two writers rebuilding
 * the same blob from two reads silently drops whichever rate landed first, and
 * nothing anywhere would report it — the month would just be missing a
 * currency. One writer removes the class of bug, and serializing writers is
 * precisely what this primitive is for.
 *
 * ## Why KV rather than serving from here
 *
 * Every device reads the same rates, and a Durable Object is one instance in
 * one place: routing every device's rate pull through it would put a
 * cross-planet round trip in front of reference data that changes once a day.
 * KV is read-replicated and cached at the edge, which is the whole shape of
 * this data. The object writes; the edge serves.
 */
export class Fx extends DurableObject<Env> {
  private readonly db: DrizzleSqliteDODatabase<typeof schema>;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = drizzle(ctx.storage, { schema, logger: false });

    ctx.blockConcurrencyWhile(async () => {
      await migrate(this.db, migrations);
    });
  }

  /** Liveness, so the binding and `exports` wiring can be tested. */
  async ping(): Promise<string> {
    return "fx";
  }

  /**
   * The daily run: ask for the latest publication, store what is new, publish.
   *
   * `asOf` is null for the ordinary case, which is what the providers want —
   * "latest" rather than today's date, because ECB does not publish at weekends
   * and asking for a Sunday by name gets Friday's rates back, correctly
   * labelled Friday. The provider is the authority on which day it answered
   * for, and that is what gets stored.
   */
  async refresh(asOf: string | null = null, now: number = Date.now()): Promise<RunOutcome> {
    const wanted = asOf === null ? supportedCurrencies : this.missingFor(asOf);
    if (wanted.length === 0) {
      return { stored: 0, covered: [], missing: [], months: [] };
    }

    const outcome = await this.waterfall(asOf, wanted, now);
    await this.publish(outcome.months);
    return outcome;
  }

  /**
   * A day nobody has needed before, asked for by a device.
   *
   * Throttled in code, against a small table of attempts. Three limits, and
   * each answers a real pattern:
   *
   * - **Already covered.** The commonest case by a distance: six devices in one
   *   group all sync the same backdated expense within a second of each other.
   * - **Chased within the hour.** A provider that had no answer an hour ago
   *   will not have one now, and a device that keeps asking should not keep
   *   spending the quota.
   * - **Chased too often.** Some dates are unanswerable — before a provider's
   *   history begins, or a currency none of them carry — and without a ceiling
   *   every device retries them forever.
   *
   * Returns whether the request was taken up, not whether a rate now exists.
   * The caller cannot act on either; it is for the log.
   */
  async backfill(asOf: string, currency: string, now: number = Date.now()): Promise<boolean> {
    // A date in the future has no publication and never will. Refused before
    // anything is recorded, so a device with a wrong clock cannot fill the
    // throttle table with dates that can never be answered.
    if (asOf > isoDay(now)) return false;

    const missing = this.missingFor(asOf);
    if (!missing.includes(currency)) return false;

    const previous = this.db.select().from(schema.backfillRequests).where(eq(schema.backfillRequests.asOf, asOf)).get();
    if (previous) {
      if (previous.attempts >= BACKFILL_ATTEMPTS) return false;
      if (now - previous.attemptedAt < BACKFILL_COOLDOWN) return false;
    }

    this.db
      .insert(schema.backfillRequests)
      .values({ asOf, attemptedAt: now, attempts: 1 })
      .onConflictDoUpdate({
        target: schema.backfillRequests.asOf,
        set: { attemptedAt: now, attempts: sql`${schema.backfillRequests.attempts} + 1` },
      })
      .run();

    const outcome = await this.waterfall(asOf, missing, now);
    await this.publish(outcome.months);
    return true;
  }

  /**
   * Every rate published on or after a date, for the client's high-water mark.
   *
   * Exists for the tests and for a device whose KV read failed; the ordinary
   * path is the edge reading the month blobs, which never wakes this object.
   */
  async since(asOf: string, limit: number): Promise<FxRate[]> {
    return this.db.select({ asOf: schema.fxRates.asOf, currency: schema.fxRates.currency, rate: schema.fxRates.rate, source: schema.fxRates.source }).from(schema.fxRates).where(gte(schema.fxRates.asOf, asOf)).orderBy(asc(schema.fxRates.asOf), asc(schema.fxRates.currency)).limit(limit).all();
  }

  /** Why a currency is missing, when one is. Read by nothing but a human. */
  async health(): Promise<(typeof schema.providerHealth.$inferSelect)[]> {
    return this.db.select().from(schema.providerHealth).all();
  }

  /**
   * Rebuilds every month blob from the rows held.
   *
   * For a KV namespace recreated, or a blob format changed. Not on any
   * schedule: the daily run republishes what it touches, which is all that
   * changes.
   */
  async republishAll(): Promise<string[]> {
    const months = this.db
      .selectDistinct({ month: sql<string>`substr(${schema.fxRates.asOf}, 1, 7)` })
      .from(schema.fxRates)
      .all()
      .map((row) => row.month);

    await this.publish(months);
    return months;
  }

  // ------------------------------------------------------------------ private

  /**
   * Runs providers in order until every currency is covered.
   *
   * Deliberately not "first success wins" — see `fx/providers.ts`. Each
   * provider fills what the ones before it could not.
   */
  private async waterfall(asOf: string | null, wanted: string[], now: number): Promise<RunOutcome> {
    const outstanding = new Set(wanted);
    const months = new Set<string>();
    let stored = 0;

    for (const provider of providers) {
      if (outstanding.size === 0) break;

      // Asking a latest-only provider for a past date would get today's rates
      // labelled as that date, which is worse than having no rate at all.
      if (asOf !== null && !provider.supportsHistory) continue;

      const { snapshot, failure } = await this.attempt(provider, asOf, [...outstanding]);
      this.recordHealth(provider.name, now, failure);
      if (!snapshot) continue;

      const rows = Object.entries(snapshot.rates)
        .filter(([code]) => outstanding.has(code))
        .map(([currency, rate]) => ({ asOf: snapshot.asOf, currency, rate, source: provider.name, createdAt: new Date(now).toISOString() }));

      if (rows.length === 0) continue;

      /**
       * Nothing already held is overwritten.
       *
       * A rate for a past date does not change, and the `source` on it has
       * been stamped onto expenses converted with it. A later provider
       * answering for the same day must not silently make that stamp wrong.
       */
      const written = this.db.insert(schema.fxRates).values(rows).onConflictDoNothing().returning({ currency: schema.fxRates.currency }).all();

      stored += written.length;
      months.add(snapshot.asOf.slice(0, 7));
      for (const { currency } of written) outstanding.delete(currency);
    }

    return { stored, covered: wanted.filter((code) => !outstanding.has(code)), missing: [...outstanding], months: [...months] };
  }

  /** One provider, with its failure turned into a value rather than a throw. */
  private async attempt(provider: FxProvider, asOf: string | null, currencies: string[]) {
    try {
      const snapshot = await provider.fetch({ asOf, currencies, env: this.env });
      return { snapshot, failure: snapshot === null ? "no usable response" : null };
    } catch (cause) {
      return { snapshot: null, failure: String(cause) };
    }
  }

  private recordHealth(name: string, now: number, failure: string | null): void {
    const at = new Date(now).toISOString();
    const row = { name, lastAttemptAt: at, lastSuccessAt: failure === null ? at : null, lastError: failure };

    this.db
      .insert(schema.providerHealth)
      .values(row)
      .onConflictDoUpdate({
        target: schema.providerHealth.name,
        // A success clears the error; a failure leaves the last success where
        // it was, so "worked yesterday, failing since" is readable.
        set: failure === null ? { lastAttemptAt: at, lastSuccessAt: at, lastError: null } : { lastAttemptAt: at, lastError: failure },
      })
      .run();
  }

  /**
   * Currencies with no rate published **on or before** a date.
   *
   * On or before, rather than on, because ECB does not publish at weekends and
   * a Friday rate is the correct answer for a Sunday. Treating a Sunday as a
   * gap would make every backfill chase rates that will never exist — and every
   * device keep asking for them.
   */
  private missingFor(asOf: string): string[] {
    const held = this.db
      .selectDistinct({ currency: schema.fxRates.currency })
      .from(schema.fxRates)
      .where(and(lte(schema.fxRates.asOf, asOf), inArray(schema.fxRates.currency, supportedCurrencies)))
      .all();

    const covered = new Set(held.map((row) => row.currency));
    return supportedCurrencies.filter((code) => !covered.has(code));
  }

  /**
   * One blob per month, written whole.
   *
   * Whole rather than merged, because this object holds every row it has ever
   * stored and can therefore rebuild the month from the truth. Read-modify-write
   * against KV would be the exact pattern its last-write-wins semantics cannot
   * support, which is the reason this object exists.
   */
  private async publish(months: string[]): Promise<void> {
    for (const month of months) {
      const rows = this.db.select({ asOf: schema.fxRates.asOf, currency: schema.fxRates.currency, rate: schema.fxRates.rate, source: schema.fxRates.source }).from(schema.fxRates).where(sql`substr(${schema.fxRates.asOf}, 1, 7) = ${month}`).orderBy(asc(schema.fxRates.asOf), asc(schema.fxRates.currency)).all();

      await this.env.CACHE.put(monthKey(month), JSON.stringify({ month, rates: rows } satisfies MonthBlob));
    }
  }
}

/** What one run of the waterfall did. Reported, never acted on. */
export interface RunOutcome {
  stored: number;
  covered: string[];
  missing: string[];
  months: string[];
}

/** An hour. A provider with no answer an hour ago does not have one now. */
const BACKFILL_COOLDOWN = 60 * 60 * 1000;

/** After this many, a date is accepted as one no provider will ever answer. */
const BACKFILL_ATTEMPTS = 5;

const isoDay = (at: number) => new Date(at).toISOString().slice(0, 10);
