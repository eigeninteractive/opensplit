import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { AppEnv } from "../context";
import { type MonthBlob, monthKey } from "../fx/blob";
import { reference, referenceEtag } from "../reference";
import { apiError, errorResponse, jsonResponse } from "../schemas/common";
import { DateSchema } from "../schemas/ledger";
import { FxBackfillRequestSchema, FxBackfillResponseSchema, FxPageSchema, type FxRate, ReferenceSchema } from "../schemas/reference";

/**
 * The two responses that are the same for everybody.
 *
 * Which is what makes them the two worth caching, and the reason they are the
 * only routes under `/api` outside the session boundary: there is nothing here
 * to scope to a reader.
 *
 * Neither touches D1, and neither wakes a Durable Object on the ordinary path.
 * Reference data is a JSON file in the bundle; rates are month blobs in KV,
 * written by the `Fx` object and read here. A rate pull is therefore an edge
 * read, which is the right shape for data that changes once a day and is read
 * by every device in every group.
 */

/**
 * How far back one request may reach.
 *
 * Fourteen months, which is the client's own window — it asks four hundred
 * days back when it holds nothing — rounded up to whole months. A device that
 * asks for more gets the most recent fourteen and `hasMore`, rather than the
 * *oldest* fourteen: serving 2020 to somebody whose clock says 2026 is the
 * answer to a question nobody asked, and it would leave their high-water mark
 * stuck six years behind with every page empty.
 */
const MAX_MONTHS = 14;

const referenceRoute = createRoute({
  method: "get",
  operationId: "getReference",
  path: "/reference",
  tags: ["reference"],
  summary: "Every currency and category the server knows about",
  description:
    "Whole rather than paged, which is proportionate rather than lazy: there are a few dozen rows between them and they change about never. Send the `ETag` back as `If-None-Match` to get a 304. The client merges with an upsert and never deletes — a category withdrawn here is still on the entries that used it.",
  request: {
    headers: z.object({
      "if-none-match": z.string().optional(),
    }),
  },
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
  description: "Against USD, which is stored as exactly 1 — so any pair is a division and there is no such thing as a supported *pair*, only a supported currency. Rates are immutable once published, so a device keeps a high-water mark rather than a cursor and asks for everything after it.",
  request: {
    query: z.object({
      since: DateSchema.openapi({ param: { name: "since", in: "query" } }),
    }),
  },
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
  description:
    "Fire and forget: a device recording an expense backdated past what the server holds says so, and the rate arrives on a later sync. It cannot wait, because a rate is display-only and must never be in the way of recording money. Heavily throttled — six devices in one group sync the same backdated expense within a second of each other.",
  request: { body: { required: true, content: { "application/json": { schema: FxBackfillRequestSchema } } } },
  responses: {
    200: jsonResponse(FxBackfillResponseSchema, "Whether this request was taken up"),
    400: errorResponse("That is not a date, or not a currency."),
  },
});

export function referenceRoutes() {
  const routes = new OpenAPIHono<AppEnv>({
    defaultHook: (result, c) => {
      if (result.success) return;
      return c.json(apiError("malformed", result.error.issues[0]?.message ?? "Invalid.", "permanent"), 400);
    },
  });

  routes.openapi(referenceRoute, (c) => {
    /**
     * Cached for a day, and revalidated by ETag.
     *
     * The ETag is a hash of the content rather than a number somebody
     * maintains, so it cannot be forgotten in the commit that edits the JSON —
     * which is the only way a response cached this long goes wrong.
     */
    c.header("ETag", referenceEtag);
    c.header("Cache-Control", "public, max-age=86400, stale-while-revalidate=604800");

    if (c.req.valid("header")["if-none-match"] === referenceEtag) {
      return c.body(null, 304);
    }
    return c.json(reference, 200);
  });

  routes.openapi(fxRoute, async (c) => {
    const { since } = c.req.valid("query");

    /**
     * Read from KV, one blob per month, never from the object.
     *
     * The `Fx` object is one instance in one place; routing every device's rate
     * pull through it would put a cross-planet round trip in front of data that
     * changes once a day and is identical for everybody. KV is
     * read-replicated. The object writes, the edge serves.
     */
    const rates: FxRate[] = [];
    const months = monthsFrom(since, new Date());

    // Anchored to today rather than to `since`: the tail of the list is the
    // recent end, and that is the half a device can use.
    const served = months.slice(-MAX_MONTHS);

    for (const month of served) {
      const blob = await c.env.CACHE.get<MonthBlob>(monthKey(month), "json");
      if (!blob) continue;
      for (const rate of blob.rates) {
        if (rate.asOf >= since) rates.push(rate);
      }
    }

    // A minute at the edge, not a day. Rates for past days never change, but
    // today's arrive on a schedule, and a device that syncs an hour after the
    // cron should not wait a day to see them.
    c.header("Cache-Control", "public, max-age=60, stale-while-revalidate=3600");

    // `hasMore` means there is older history this page did not reach, which is
    // the opposite direction from every other cursor in this API — and it is
    // why it is a flag rather than a cursor: rates are immutable, so a device
    // that wants the older end asks for it by name rather than paging to it.
    return c.json({ rates, hasMore: months.length > served.length }, 200);
  });

  routes.openapi(backfillRoute, async (c) => {
    const { asOf, currency } = c.req.valid("json");
    const accepted = await c.env.FX.getByName("global").backfill(asOf, currency);
    return c.json({ accepted }, 200);
  });

  return routes;
}

/**
 * Every `YYYY-MM` from a date to now, oldest first.
 *
 * Walked month by month rather than derived, because a device that has been
 * offline for a year asks for a year and the answer has to be the months that
 * exist between the two dates — not a count, which is where an off-by-one puts
 * a gap in somebody's history.
 */
export function monthsFrom(since: string, now: Date): string[] {
  const months: string[] = [];
  const end = now.getUTCFullYear() * 12 + now.getUTCMonth();

  let year = Number(since.slice(0, 4));
  let month = Number(since.slice(5, 7)) - 1;

  // A `since` in the future yields nothing, which is the honest answer: there
  // are no publications after today.
  while (year * 12 + month <= end) {
    months.push(`${year}-${String(month + 1).padStart(2, "0")}`);
    month += 1;
    if (month === 12) {
      month = 0;
      year += 1;
    }
  }
  return months;
}
