import { z } from "@hono/zod-openapi";
import { IdSchema } from "./common";
import { CurrencySchema, DateSchema } from "./ledger";

/**
 * Reference data and exchange rates: the two responses that are the same for
 * everybody.
 *
 * Which is also what makes them the two worth caching at the edge. Everything
 * else in this API is scoped to who is asking; these are public, so the
 * session read before serving them would buy nothing.
 */

export const CurrencySchemaRow = z
  .object({
    code: CurrencySchema,

    /**
     * How many minor units make a major one, as ISO 4217 defines it.
     *
     * Not decoration. Every amount in this app is an integer of minor units,
     * so this is what decides whether `1000` is ten dollars, a thousand yen or
     * one dinar — and getting it wrong is a factor-of-a-thousand error in
     * somebody's balance rather than a formatting quirk.
     */
    exponent: z.int().min(0).max(4),
    symbol: z.string().nullable(),
    name: z.string(),
  })
  .openapi("Currency");

export const CategorySchema = z
  .object({
    /**
     * Written onto entries, so it is permanent.
     *
     * Changing one orphans every expense that used it, on every device that has
     * already synced, and the only symptom is a category quietly failing to
     * render.
     */
    id: IdSchema,
    name: z.string(),

    /** A Material icon name, resolved by the client's own icon table. */
    icon: z.string(),
  })
  .openapi("Category");

export const ReferenceSchema = z
  .object({
    currencies: z.array(CurrencySchemaRow),
    categories: z.array(CategorySchema),
  })
  .openapi("Reference");

/**
 * One published rate, against USD.
 *
 * USD is the pivot and is stored as exactly 1, so any pair is a division and
 * there is no such thing as a supported *pair* — only a supported currency.
 */
export const FxRateSchema = z
  .object({
    /** Publication date, `YYYY-MM-DD`. A rate belongs to a day, not an instant. */
    asOf: DateSchema,
    currency: CurrencySchema,

    /** Units of `currency` per one USD. */
    rate: z.number().positive(),

    /**
     * Which provider supplied this row.
     *
     * Rows for one day can come from different providers, because the
     * waterfall fills gaps rather than stopping at the first success. Carried
     * to the device because it is stamped onto any expense converted with it —
     * a converted amount that cannot say where its rate came from is a number
     * nobody can check afterwards.
     */
    source: z.string(),
  })
  .openapi("FxRate");

export const FxPageSchema = z
  .object({
    rates: z.array(FxRateSchema),

    /**
     * Whether the window was cut short.
     *
     * A device with no rates at all asks for a bounded window rather than all
     * history, so this says whether there is more behind it — but nothing acts
     * on it today, because rates are immutable and the high-water mark walks
     * forward on its own.
     */
    hasMore: z.boolean(),
  })
  .openapi("FxPage");

/**
 * Asking for a day nobody has needed before.
 *
 * Fire and forget: the device records an expense backdated past what the server
 * holds, says so, and the rate arrives on a later sync. It cannot wait, because
 * a rate is display-only and must never be in the way of recording money.
 */
export const FxBackfillRequestSchema = z
  .object({
    asOf: DateSchema,
    currency: CurrencySchema,
  })
  .openapi("FxBackfillRequest");

export const FxBackfillResponseSchema = z
  .object({
    /**
     * Whether this one was taken up, rather than whether a rate now exists.
     *
     * False for a day already covered, a request repeated within the hour, or
     * one past the ceiling — all of which are ordinary, and none of which the
     * caller does anything about. It is here so a log can tell a throttled
     * request from a served one.
     */
    accepted: z.boolean(),
  })
  .openapi("FxBackfillResponse");

export type Currency = z.infer<typeof CurrencySchemaRow>;
export type Category = z.infer<typeof CategorySchema>;
export type Reference = z.infer<typeof ReferenceSchema>;
export type FxRate = z.infer<typeof FxRateSchema>;
export type FxPage = z.infer<typeof FxPageSchema>;
export type FxBackfillRequest = z.infer<typeof FxBackfillRequestSchema>;
