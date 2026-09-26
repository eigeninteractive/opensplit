import { z } from "@hono/zod-openapi";

import { fxRates } from "../db/fx/schema";
import { CurrencyCodeSchema, createSelectSchema, DateSchema, IdSchema } from "./common";

/** Reference data and exchange rates: the same for everybody, so public and edge-cached. */

export const CurrencySchema = z
  .object({
    code: CurrencyCodeSchema,
    /** Minor units per major (ISO 4217). Every amount is an integer of minor units. */
    exponent: z.int().min(0).max(4),
    symbol: z.string().nullable(),
    name: z.string(),
  })
  .openapi("Currency");

export const CategorySchema = z
  .object({
    /** Written onto entries, so permanent. */
    id: IdSchema,
    name: z.string(),
    /** A Material icon name. */
    icon: z.string(),
  })
  .openapi("Category");

export const ReferenceSchema = z
  .object({
    currencies: z.array(CurrencySchema),
    categories: z.array(CategorySchema),
  })
  .openapi("Reference");

const fxRateRow = createSelectSchema(fxRates, { asOf: () => DateSchema, currency: () => CurrencyCodeSchema, rate: () => z.number().positive() });

/** One published rate against USD, so any pair is a division. */
export const FxRateSchema = fxRateRow.omit({ createdAt: true }).openapi("FxRate");

export const FxPageSchema = z
  .object({
    rates: z.array(FxRateSchema),
    /** Whether older history exists beyond this window. */
    hasMore: z.boolean(),
  })
  .openapi("FxPage");

/** Ask for a day the server has never needed; the rate arrives on a later sync. */
export const FxBackfillRequestSchema = fxRateRow.pick({ asOf: true, currency: true }).openapi("FxBackfillRequest");

/** Whether this request was taken up (false for a covered, throttled or future day). */
export const FxBackfillResponseSchema = z.object({ accepted: z.boolean() }).openapi("FxBackfillResponse");

export type Currency = z.infer<typeof CurrencySchema>;
export type Category = z.infer<typeof CategorySchema>;
export type Reference = z.infer<typeof ReferenceSchema>;
export type FxRate = z.infer<typeof FxRateSchema>;
export type FxPage = z.infer<typeof FxPageSchema>;
