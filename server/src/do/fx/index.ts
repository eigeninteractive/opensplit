import { DurableObject } from "cloudflare:workers";
import { and, asc, between, eq, gte, inArray, lte, sql } from "drizzle-orm";
import { type DrizzleSqliteDODatabase, drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import * as schema from "../../db/fx/schema";
import { type MonthBlob, monthKey } from "../../fx/blob";
import { type FxProvider, providers } from "../../fx/providers";
import { supportedCurrencies } from "../../reference";
import type { FxRate } from "../../schemas/reference";
import migrations from "./migrations/migrations";

/**
 * The only writer of exchange rates: a singleton (`getByName("global")`) that
 * keeps the history in its own SQLite and publishes one blob per month to KV.
 *
 * A single writer because KV is last-write-wins: the daily run and a backfill
 * rebuilding the same month from two reads would silently drop a rate. KV
 * rather than serving from here because every device reads the same rates, and
 * the edge replicates them.
 */
export class Fx extends DurableObject<Env> {
  private readonly db: DrizzleSqliteDODatabase<typeof schema>;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = drizzle(ctx.storage, { schema, logger: false });
    ctx.blockConcurrencyWhile(() => migrate(this.db, migrations));
  }

  async ping(): Promise<string> {
    return "fx";
  }

  /**
   * The daily run, for the latest publication (null `asOf`): the provider says
   * which day it answered for, since ECB gives Friday's rates for a Sunday.
   */
  async refresh(asOf: string | null = null, now: number = Date.now()): Promise<RunOutcome> {
    const wanted = asOf === null ? supportedCurrencies : this.missingFor(asOf);
    if (wanted.length === 0) return { stored: 0, covered: [], missing: [], months: [] };

    const outcome = await this.waterfall(asOf, wanted, now);
    await this.publish(outcome.months);
    return outcome;
  }

  /**
   * A day a device asked for. Throttled: already covered, chased within the
   * hour, or chased too often is not taken up. Returns whether it was, for the log.
   */
  async backfill(asOf: string, currency: string, now: number = Date.now()): Promise<boolean> {
    // A future date never publishes; refused before a wrong clock can fill the throttle table.
    if (asOf > isoDay(now)) return false;

    const missing = this.missingFor(asOf);
    if (!missing.includes(currency)) return false;

    const previous = this.db.select().from(schema.backfillRequests).where(eq(schema.backfillRequests.asOf, asOf)).get();
    if (previous && (previous.attempts >= BACKFILL_ATTEMPTS || now - previous.attemptedAt < BACKFILL_COOLDOWN)) return false;

    this.db
      .insert(schema.backfillRequests)
      .values({ asOf, attemptedAt: now, attempts: 1 })
      .onConflictDoUpdate({ target: schema.backfillRequests.asOf, set: { attemptedAt: now, attempts: sql`${schema.backfillRequests.attempts} + 1` } })
      .run();

    const outcome = await this.waterfall(asOf, missing, now);
    await this.publish(outcome.months);
    return true;
  }

  /** Rates on or after a day, straight from storage. */
  async since(asOf: string, limit: number): Promise<FxRate[]> {
    return this.db.select(rateColumns).from(schema.fxRates).where(gte(schema.fxRates.asOf, asOf)).orderBy(asc(schema.fxRates.asOf), asc(schema.fxRates.currency)).limit(limit).all();
  }

  /** Why a currency is missing, for a human. */
  async health(): Promise<(typeof schema.providerHealth.$inferSelect)[]> {
    return this.db.select().from(schema.providerHealth).all();
  }

  /** Rebuilds every month blob, for a recreated KV namespace or a changed blob format. */
  async republishAll(): Promise<string[]> {
    const months = this.db
      .selectDistinct({ month: sql<string>`substr(${schema.fxRates.asOf}, 1, 7)` })
      .from(schema.fxRates)
      .all()
      .map((row) => row.month);
    await this.publish(months);
    return months;
  }

  /** Providers in order, each filling what the ones before it could not. */
  private async waterfall(asOf: string | null, wanted: string[], now: number): Promise<RunOutcome> {
    const outstanding = new Set(wanted);
    const months = new Set<string>();
    let stored = 0;

    for (const provider of providers) {
      if (outstanding.size === 0) break;
      // A latest-only provider asked for a past date would mislabel today's rates.
      if (asOf !== null && !provider.supportsHistory) continue;

      const { snapshot, failure } = await this.attempt(provider, asOf, [...outstanding]);
      this.recordHealth(provider.name, now, failure);
      if (!snapshot) continue;

      const rows = Object.entries(snapshot.rates)
        .filter(([code]) => outstanding.has(code))
        .map(([currency, rate]) => ({ asOf: snapshot.asOf, currency, rate, source: provider.name, createdAt: new Date(now).toISOString() }));
      if (rows.length === 0) continue;

      // Never overwritten: the `source` is stamped on expenses converted with the rate.
      const written = this.db.insert(schema.fxRates).values(rows).onConflictDoNothing().returning({ currency: schema.fxRates.currency }).all();
      stored += written.length;
      months.add(snapshot.asOf.slice(0, 7));
      for (const { currency } of written) outstanding.delete(currency);
    }

    return { stored, covered: wanted.filter((code) => !outstanding.has(code)), missing: [...outstanding], months: [...months] };
  }

  private async attempt(provider: FxProvider, asOf: string | null, currencies: string[]) {
    try {
      const snapshot = await provider.fetch({ asOf, currencies, env: this.env });
      return { snapshot, failure: snapshot === null ? "no usable response" : null };
    } catch (cause) {
      return { snapshot: null, failure: String(cause) };
    }
  }

  /** A failure keeps the last success, so "worked yesterday, failing since" is readable. */
  private recordHealth(name: string, now: number, failure: string | null): void {
    const at = new Date(now).toISOString();
    this.db
      .insert(schema.providerHealth)
      .values({ name, lastAttemptAt: at, lastSuccessAt: failure === null ? at : null, lastError: failure })
      .onConflictDoUpdate({
        target: schema.providerHealth.name,
        set: failure === null ? { lastAttemptAt: at, lastSuccessAt: at, lastError: null } : { lastAttemptAt: at, lastError: failure },
      })
      .run();
  }

  /** Currencies with no rate on or before a day: a Friday rate answers a Sunday. */
  private missingFor(asOf: string): string[] {
    const held = this.db
      .selectDistinct({ currency: schema.fxRates.currency })
      .from(schema.fxRates)
      .where(and(lte(schema.fxRates.asOf, asOf), inArray(schema.fxRates.currency, supportedCurrencies)))
      .all();
    const covered = new Set(held.map((row) => row.currency));
    return supportedCurrencies.filter((code) => !covered.has(code));
  }

  /** Each month rewritten whole from the rows held; a read-modify-write is what KV cannot do safely. */
  private async publish(months: string[]): Promise<void> {
    for (const month of months) {
      const rates = this.db
        .select(rateColumns)
        .from(schema.fxRates)
        .where(between(schema.fxRates.asOf, `${month}-01`, `${month}-31`))
        .orderBy(asc(schema.fxRates.asOf), asc(schema.fxRates.currency))
        .all();
      await this.env.CACHE.put(monthKey(month), JSON.stringify({ month, rates } satisfies MonthBlob));
    }
  }
}

const rateColumns = { asOf: schema.fxRates.asOf, currency: schema.fxRates.currency, rate: schema.fxRates.rate, source: schema.fxRates.source };

export interface RunOutcome {
  stored: number;
  covered: string[];
  missing: string[];
  months: string[];
}

const BACKFILL_COOLDOWN = 60 * 60 * 1000;
/** After this many, a date is accepted as one no provider will answer. */
const BACKFILL_ATTEMPTS = 5;

const isoDay = (at: number) => new Date(at).toISOString().slice(0, 10);
