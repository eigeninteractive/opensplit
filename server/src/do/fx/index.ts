import { DurableObject } from "cloudflare:workers";
import { and, asc, between, eq, gte, inArray, sql } from "drizzle-orm";
import { type DrizzleSqliteDODatabase, drizzle } from "drizzle-orm/durable-sqlite";
import { migrate } from "drizzle-orm/durable-sqlite/migrator";

import { insertable } from "../../chunked";
import * as schema from "../../db/fx/schema";
import { type MonthBlob, monthKey } from "../../fx/blob";
import { type FxProvider, type FxSnapshot, providers } from "../../fx/providers";
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
  private readonly db: DrizzleSqliteDODatabase;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.db = drizzle(ctx.storage, { logger: false });
    ctx.blockConcurrencyWhile(async () => migrate(this.db, migrations));
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

  /**
   * Keeps the last [HISTORY_DAYS] free of any stretch longer than
   * [STALE_AFTER_DAYS] without a publication, since a rate that old does not
   * answer for a day. Each such stretch is fetched whole, in one request, from
   * the first provider that can answer for a range. Run daily: on a new
   * deployment the first run fills the year, and every run after finds
   * nothing to do unless a provider was down for a week.
   */
  async fillHistory(now: number = Date.now()): Promise<HistoryOutcome> {
    const gaps = this.gaps(now);
    const months = new Set<string>();
    let stored = 0;

    for (const gap of gaps) {
      for (const provider of providers) {
        if (!provider.fetchRange) continue;
        const { snapshots, failure } = await this.attemptRange(provider, gap);
        this.recordHealth(provider.name, now, failure);
        if (!snapshots) continue;

        for (const snapshot of snapshots) {
          const written = this.store(snapshot, provider.name, now);
          stored += written.length;
          if (written.length > 0) months.add(snapshot.asOf.slice(0, 7));
        }
        break;
      }
    }

    await this.publish([...months]);
    return { gaps, stored, months: [...months].sort() };
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

      const answered = Object.entries(snapshot.rates).filter(([code]) => outstanding.has(code));
      const written = this.store({ asOf: snapshot.asOf, rates: Object.fromEntries(answered) }, provider.name, now);
      // Covered whether written now or already held: a second run on the same day asks nobody else for it.
      for (const [currency] of answered) outstanding.delete(currency);
      if (written.length === 0) continue;

      stored += written.length;
      months.add(snapshot.asOf.slice(0, 7));
    }

    return { stored, covered: wanted.filter((code) => !outstanding.has(code)), missing: [...outstanding], months: [...months] };
  }

  /**
   * Stores one day's rates and returns the currencies newly written. Never
   * overwrites: the `source` is stamped on expenses converted with a rate.
   * In pieces, since one statement carries at most 100 values.
   */
  private store(snapshot: FxSnapshot, source: string, now: number): string[] {
    const createdAt = new Date(now).toISOString();
    const rows = Object.entries(snapshot.rates).map(([currency, rate]) => ({ asOf: snapshot.asOf, currency, rate, source, createdAt }));
    return insertable(rows).flatMap((chunk) =>
      this.db
        .insert(schema.fxRates)
        .values(chunk)
        .onConflictDoNothing()
        .returning({ currency: schema.fxRates.currency })
        .all()
        .map((row) => row.currency),
    );
  }

  /**
   * Stretches of the last year where some day has no publication within
   * [STALE_AFTER_DAYS] before it, each as the run of days between the
   * publications either side. The edges of the year count as publications.
   */
  private gaps(now: number): Gap[] {
    const today = isoDay(now);
    const floor = shiftDay(today, -HISTORY_DAYS);
    const published = this.db
      .selectDistinct({ asOf: schema.fxRates.asOf })
      .from(schema.fxRates)
      .where(between(schema.fxRates.asOf, floor, today))
      .orderBy(asc(schema.fxRates.asOf))
      .all()
      .map((row) => row.asOf);

    const gaps: Gap[] = [];
    let before = shiftDay(floor, -1);
    for (const after of [...published, shiftDay(today, 1)]) {
      if (daysBetween(before, after) > STALE_AFTER_DAYS + 1) gaps.push({ from: shiftDay(before, 1), to: shiftDay(after, -1) });
      before = after;
    }
    return gaps;
  }

  private async attemptRange(provider: FxProvider, { from, to }: Gap) {
    try {
      const snapshots = (await provider.fetchRange?.({ from, to, currencies: supportedCurrencies, env: this.env })) ?? null;
      return { snapshots, failure: snapshots === null ? "no usable response for a range" : null };
    } catch (cause) {
      return { snapshots: null, failure: String(cause) };
    }
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

  /**
   * Currencies with no rate that answers for a day: one published on it or in
   * the [STALE_AFTER_DAYS] before, so Friday's answers a Sunday and last
   * spring's does not answer today.
   */
  private missingFor(asOf: string): string[] {
    const held = this.db
      .selectDistinct({ currency: schema.fxRates.currency })
      .from(schema.fxRates)
      .where(and(between(schema.fxRates.asOf, shiftDay(asOf, -STALE_AFTER_DAYS), asOf), inArray(schema.fxRates.currency, supportedCurrencies)))
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

/** How far back history is kept complete: the client's own rate window. */
export const HISTORY_DAYS = 365;

/**
 * How old a rate may be and still answer for a day. A week covers every
 * weekend and every ECB holiday. The app holds the same rule, in
 * `lib/domain/fx/fx_quote.dart`, for the rates it looks up itself.
 */
export const STALE_AFTER_DAYS = 7;

/** A run of days, `YYYY-MM-DD`, inclusive. */
export interface Gap {
  from: string;
  to: string;
}

export interface HistoryOutcome {
  gaps: Gap[];
  stored: number;
  months: string[];
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

const DAY = 24 * 60 * 60 * 1000;
const isoDay = (at: number) => new Date(at).toISOString().slice(0, 10);
const shiftDay = (day: string, by: number) => isoDay(Date.parse(day) + by * DAY);
const daysBetween = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / DAY);
