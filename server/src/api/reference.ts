import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";

import type { AppEnv } from "../context";
import { type MonthBlob, monthKey } from "../fx/blob";
import { reference, referenceEtag } from "../reference";
import { DateSchema, errorResponse, jsonBody, jsonResponse } from "../schemas/common";
import { FxBackfillRequestSchema, FxBackfillResponseSchema, FxPageSchema, ReferenceSchema } from "../schemas/reference";

/**
 * The responses that are the same for everybody, so outside the session and
 * edge-cached. Reference data is bundled; rates are month blobs in KV that the
 * `Fx` object writes.
 */

/** The client's own window (about 400 days), in whole months. */
const MAX_MONTHS = 14;

const referenceRoute = createRoute({
  method: "get",
  operationId: "getReference",
  path: "/reference",
  tags: ["reference"],
  summary: "Every currency and category the server knows about",
  description: "Send the `ETag` back as `If-None-Match` to get a 304.",
  request: { headers: z.object({ "if-none-match": z.string().optional() }) },
  responses: {
    200: jsonResponse(ReferenceSchema, "Currencies and categories"),
    304: { description: "Unchanged since the ETag you sent." },
  },
});

const fxRoute = createRoute({
  method: "get",
  operationId: "getFxRates",
  path: "/fx",
  tags: ["reference"],
  summary: "Exchange rates published on or after a date",
  description: "Against USD. Rates are immutable, so a device keeps a high-water mark and asks for everything after it; the most recent months are served when the window is too wide.",
  request: { query: z.object({ since: DateSchema.openapi({ param: { name: "since", in: "query" } }) }) },
  responses: {
    200: jsonResponse(FxPageSchema, "The rates, oldest first"),
    400: errorResponse("That is not a date."),
  },
});

const backfillRoute = createRoute({
  method: "post",
  operationId: "requestFxBackfill",
  path: "/fx/backfill",
  tags: ["reference"],
  summary: "Ask for a day the server has never needed",
  description: "Fire and forget, and heavily throttled: the rate arrives on a later sync.",
  request: { body: jsonBody(FxBackfillRequestSchema) },
  responses: {
    200: jsonResponse(FxBackfillResponseSchema, "Whether this request was taken up"),
    400: errorResponse("That is not a date, or not a currency."),
  },
});

export function referenceRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(referenceRoute, (c) => {
    c.header("ETag", referenceEtag);
    c.header("Cache-Control", "public, max-age=86400, stale-while-revalidate=604800");
    if (c.req.valid("header")["if-none-match"] === referenceEtag) return c.body(null, 304);
    return c.json(reference, 200);
  });

  routes.openapi(fxRoute, async (c) => {
    const { since } = c.req.valid("query");
    const months = monthsFrom(since, new Date());
    const served = months.slice(-MAX_MONTHS);
    const blobs = await Promise.all(served.map((month) => c.env.CACHE.get<MonthBlob>(monthKey(month), "json")));
    const rates = blobs.flatMap((blob) => blob?.rates ?? []).filter((rate) => rate.asOf >= since);

    // A minute, not a day: today's rates arrive on a schedule.
    c.header("Cache-Control", "public, max-age=60, stale-while-revalidate=3600");
    return c.json({ rates, hasMore: months.length > served.length }, 200);
  });

  routes.openapi(backfillRoute, async (c) => {
    const { asOf, currency } = c.req.valid("json");
    return c.json({ accepted: await c.env.FX.getByName("global").backfill(asOf, currency) }, 200);
  });
}

/** Every `YYYY-MM` from a date to now, oldest first; none for a future date. */
export function monthsFrom(since: string, now: Date): string[] {
  const months: string[] = [];
  const end = now.getUTCFullYear() * 12 + now.getUTCMonth();
  for (let index = Number(since.slice(0, 4)) * 12 + Number(since.slice(5, 7)) - 1; index <= end; index++) {
    months.push(`${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, "0")}`);
  }
  return months;
}
