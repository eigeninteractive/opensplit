import { env, exports as workerExports } from "cloudflare:workers";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { monthsFrom } from "../src/api/reference";
import { type MonthBlob, monthKey } from "../src/fx/blob";
import { reference, referenceEtag, supportedCurrencies } from "../src/reference";
import type { FxPage, Reference } from "../src/schemas/reference";

/**
 * Rates, and the object that is their only writer.
 *
 * The waterfall runs against a stubbed `fetch` rather than the real providers,
 * which is not a compromise: what is under test is the *ordering* — that a
 * second provider fills what the first could not, that a latest-only source is
 * never asked for a past date, that nothing already stored is overwritten — and
 * none of that is a property of Frankfurter or ExchangeRate-API. Reaching the
 * live services would make the suite depend on somebody else's uptime to answer
 * a question about our own code.
 *
 * The one thing the stub cannot check is whether the adapters parse what those
 * services really send. That is a real gap, and the honest place for it is a
 * manual run against the live API, not a test that fails on a Tuesday because
 * ECB had an outage.
 */

const ORIGIN = "https://opensplit.test";

/** A `fetch` that answers from a script, and records what it was asked. */
function stubFetch(script: (url: string) => unknown | null) {
  const calls: string[] = [];

  vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

    // Anything not a provider call goes nowhere near the script: the Worker's
    // own routes are reached through `workerExports.default.fetch`, not this.
    calls.push(url);
    const body = script(url);
    if (body === null) return new Response("nope", { status: 503 });
    return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
  });

  return calls;
}

/** Frankfurter's shape: ECB's ~30 currencies, and a date it chose itself. */
function frankfurterBody(date: string, rates: Record<string, number>) {
  return { amount: 1, base: "USD", date, rates };
}

/** ExchangeRate-API's shape: everything, and a unix timestamp. */
function exchangerateBody(unix: number, rates: Record<string, number>) {
  return { result: "success", time_last_update_unix: unix, conversion_rates: rates };
}

function fx() {
  return env.FX.getByName(`fx-${crypto.randomUUID()}`);
}

/**
 * Both providers available, which is the configured deployment.
 *
 * `.dev.vars` leaves the key empty, because an empty key is what a fork or a
 * local run has — and the adapter skipping itself on one is a behaviour with
 * its own test below. Everything about the *ordering* needs two live sources,
 * so this file configures them.
 */
beforeAll(() => {
  env.EXCHANGERATE_API_KEY = "test-key";
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("the waterfall", () => {
  it("lets a second provider fill what the first could not", async () => {
    // ECB publishes EUR and GBP and not AED, which is the whole reason there
    // is more than one provider: stopping at a perfectly successful response
    // would leave a fifth of the supported currencies permanently absent.
    const calls = stubFetch((url) => {
      if (url.includes("frankfurter")) return frankfurterBody("2026-09-24", { EUR: 0.92, GBP: 0.78 });
      if (url.includes("exchangerate-api")) return exchangerateBody(Date.parse("2026-09-24T00:00:00Z") / 1000, Object.fromEntries(supportedCurrencies.map((code) => [code, 7])));
      return null;
    });

    const object = fx();
    const outcome = await object.refresh();

    expect(outcome.missing).toEqual([]);
    expect(outcome.covered.sort()).toEqual([...supportedCurrencies].sort());
    expect(calls.some((url) => url.includes("frankfurter"))).toBe(true);
    expect(calls.some((url) => url.includes("exchangerate-api"))).toBe(true);

    const rates = await object.since("2026-09-24", 100);
    // Each row records who supplied it, because that gets stamped onto any
    // expense converted with it.
    expect(rates.find((rate) => rate.currency === "EUR")?.source).toBe("frankfurter");
    expect(rates.find((rate) => rate.currency === "AED")?.source).toBe("exchangerate_v6");
  });

  it("does not ask a second provider once everything is covered", async () => {
    const calls = stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", Object.fromEntries(supportedCurrencies.map((code) => [code, 3]))) : null));

    await fx().refresh();

    // A quota is 1,500 requests a month. Asking a second source for nothing is
    // not free, and the loop exits on coverage rather than running the list.
    expect(calls.filter((url) => url.includes("exchangerate-api"))).toEqual([]);
  });

  it("never asks a latest-only provider for a past date", async () => {
    const calls = stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-08-14", { EUR: 0.9 }) : exchangerateBody(0, { AED: 3.67 })));

    await fx().refresh("2026-08-14");

    // ExchangeRate-API's history endpoint answers `plan-upgrade-required` on
    // the free plan, so asking it for a past date gets today's rates labelled
    // as that date — which is worse than having no rate at all.
    expect(calls.filter((url) => url.includes("exchangerate-api"))).toEqual([]);
  });

  it("keeps the provider's own date, not the one it was asked for", async () => {
    // ECB does not publish at weekends, so asking for a Sunday legitimately
    // returns Friday's — and labelling Friday's numbers as Sunday's would be
    // inventing data.
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-25", { EUR: 0.92 }) : null));

    const object = fx();
    await object.refresh("2026-09-27");

    const stored = await object.since("2026-01-01", 100);
    expect(new Set(stored.map((rate) => rate.asOf))).toEqual(new Set(["2026-09-25"]));
  });

  it("never overwrites a rate it already holds", async () => {
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 0.92 }) : null));
    const object = fx();
    await object.refresh();

    vi.unstubAllGlobals();
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 9.99 }) : null));
    await object.refresh("2026-09-24");

    // A rate for a past date does not change, and its `source` has been
    // stamped onto expenses converted with it. A second answer for the same
    // day must not make that stamp quietly wrong.
    const stored = await object.since("2026-09-24", 100);
    expect(stored.find((rate) => rate.currency === "EUR")?.rate).toBe(0.92);
  });

  it("skips a provider with no key rather than failing the run", async () => {
    // How a fork, or a local `wrangler dev`, runs on Frankfurter alone without
    // editing anything. An unconfigured source is not a broken one.
    env.EXCHANGERATE_API_KEY = "";
    const calls = stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 0.92 }) : null));

    const outcome = await fx().refresh();
    env.EXCHANGERATE_API_KEY = "test-key";

    expect(calls.filter((url) => url.includes("exchangerate-api"))).toEqual([]);
    expect(outcome.covered).toContain("EUR");
    // And the currencies ECB does not publish are simply missing, which is a
    // reported outcome rather than a failure.
    expect(outcome.missing).toContain("AED");
  });

  it("records why a provider failed, and clears it on the next success", async () => {
    stubFetch(() => null);
    const object = fx();
    await object.refresh();

    const failing = (await object.health()).find((row) => row.name === "frankfurter");
    expect(failing?.lastError).toBe("no usable response");
    expect(failing?.lastSuccessAt).toBeNull();

    vi.unstubAllGlobals();
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 0.92 }) : null));
    await object.refresh();

    // "Why is AED missing" is otherwise unanswerable from outside, and a stale
    // error left behind after a recovery is worse than none.
    const recovered = (await object.health()).find((row) => row.name === "frankfurter");
    expect(recovered?.lastError).toBeNull();
    expect(recovered?.lastSuccessAt).not.toBeNull();
  });
});

describe("a backfill", () => {
  it("is refused for a day already covered", async () => {
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", Object.fromEntries(supportedCurrencies.map((code) => [code, 3]))) : null));

    const object = fx();
    await object.refresh();

    // Six devices in one group sync the same backdated expense within a second
    // of each other. This is the commonest case by a distance.
    expect(await object.backfill("2026-09-25", "INR")).toBe(false);
  });

  it("is refused a second time within the hour, and again after too many", async () => {
    stubFetch(() => null);
    const object = fx();
    const at = Date.parse("2026-09-24T12:00:00Z");

    expect(await object.backfill("2026-08-01", "INR", at)).toBe(true);
    // A provider with no answer an hour ago does not have one now.
    expect(await object.backfill("2026-08-01", "INR", at + 60_000)).toBe(false);
    expect(await object.backfill("2026-08-01", "INR", at + 2 * 60 * 60 * 1000)).toBe(true);

    // Some dates are unanswerable — before a provider's history begins, or a
    // currency none of them carry. Without a ceiling every device retries them
    // forever, against a quota.
    let clock = at + 4 * 60 * 60 * 1000;
    for (let attempt = 0; attempt < 3; attempt++) {
      await object.backfill("2026-08-01", "INR", clock);
      clock += 2 * 60 * 60 * 1000;
    }
    expect(await object.backfill("2026-08-01", "INR", clock)).toBe(false);
  });

  it("is refused for a date that has not happened", async () => {
    stubFetch(() => null);
    // A device with a wrong clock would otherwise fill the throttle table with
    // dates no provider can ever answer.
    expect(await fx().backfill("2099-01-01", "INR")).toBe(false);
  });
});

describe("the month blobs", () => {
  it("are written whole, from what the object holds", async () => {
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 0.92, GBP: 0.78 }) : null));

    const object = fx();
    await object.refresh();

    const blob = await env.CACHE.get<MonthBlob>(monthKey("2026-09"), "json");
    expect(blob?.month).toBe("2026-09");
    expect(blob?.rates.map((rate) => rate.currency).sort()).toEqual(["EUR", "GBP", "USD"]);

    // Whole rather than merged, because the object holds every row it ever
    // stored and can rebuild the month from the truth. Read-modify-write
    // against KV is the exact pattern its last-write-wins semantics cannot
    // support, which is why this object is a singleton.
    vi.unstubAllGlobals();
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-25", { EUR: 0.93, SGD: 1.29 }) : null));
    await object.refresh();

    const after = await env.CACHE.get<MonthBlob>(monthKey("2026-09"), "json");
    expect(after?.rates.filter((rate) => rate.asOf === "2026-09-24")).toHaveLength(3);
    // EUR appears on both days, and correctly: `(as_of, currency)` is the key,
    // so a new day is a new row rather than a conflict with the old one.
    expect(
      after?.rates
        .filter((rate) => rate.asOf === "2026-09-25")
        .map((rate) => rate.currency)
        .sort(),
    ).toEqual(["EUR", "SGD", "USD"]);
  });
});

describe("monthsFrom", () => {
  it("walks the months between two dates, inclusive", () => {
    expect(monthsFrom("2026-09-24", new Date("2026-09-30T00:00:00Z"))).toEqual(["2026-09"]);
    expect(monthsFrom("2025-11-02", new Date("2026-02-14T00:00:00Z"))).toEqual(["2025-11", "2025-12", "2026-01", "2026-02"]);
  });

  it("answers nothing for a date that has not happened", () => {
    // There are no publications after today, and a device with a clock a day
    // ahead should get an empty page rather than a year of missing blobs.
    expect(monthsFrom("2027-01-01", new Date("2026-09-24T00:00:00Z"))).toEqual([]);
  });
});

describe("the reference route", () => {
  it("serves the bundled data, and a 304 for an unchanged ETag", async () => {
    const response = await workerExports.default.fetch(`${ORIGIN}/api/reference`);
    expect(response.status).toBe(200);

    const body = (await response.json()) as Reference;
    expect(body.currencies).toHaveLength(reference.currencies.length);
    expect(body.categories).toHaveLength(reference.categories.length);

    const etag = response.headers.get("ETag");
    expect(etag).toBe(referenceEtag);

    const again = await workerExports.default.fetch(`${ORIGIN}/api/reference`, { headers: { "If-None-Match": etag ?? "" } });
    expect(again.status).toBe(304);
  });

  it("needs no session, because it is the same for everybody", async () => {
    // `using (true)` in SQL said the same thing at more length. A session read
    // here would buy nothing and cost a D1 round trip on the response most
    // worth caching.
    expect((await workerExports.default.fetch(`${ORIGIN}/api/reference`)).status).toBe(200);
  });

  it("carries an exponent for every currency, because amounts are integers", async () => {
    const body = (await workerExports.default.fetch(`${ORIGIN}/api/reference`).then((r) => r.json())) as Reference;

    // Getting one wrong is a factor-of-a-thousand error in somebody's balance
    // rather than a formatting quirk: JPY and KRW have no minor unit at all,
    // and KWD and BHD have three.
    expect(body.currencies.find((currency) => currency.code === "JPY")?.exponent).toBe(0);
    expect(body.currencies.find((currency) => currency.code === "KWD")?.exponent).toBe(3);
    expect(body.currencies.every((currency) => currency.name.length > 0)).toBe(true);
  });
});

describe("the fx route", () => {
  beforeEach(async () => {
    stubFetch((url) => (url.includes("frankfurter") ? frankfurterBody("2026-09-24", { EUR: 0.92 }) : null));
    // The route reads KV, so something has to have published into it. The
    // singleton is shared by the whole test file, which is what production
    // does too.
    await env.FX.getByName("global").refresh();
    vi.unstubAllGlobals();
  });

  it("reads from KV rather than waking the object", async () => {
    const response = await workerExports.default.fetch(`${ORIGIN}/api/fx?since=2026-09-01`);
    expect(response.status).toBe(200);

    const page = (await response.json()) as FxPage;
    expect(page.rates.some((rate) => rate.currency === "EUR")).toBe(true);
    expect(page.hasMore).toBe(false);

    // Cached at the edge for a minute, not a day: past days never change, but
    // today's arrive on a schedule and a device syncing an hour after the cron
    // should not wait a day to see them.
    expect(response.headers.get("Cache-Control")).toContain("max-age=60");
  });

  it("refuses something that is not a date", async () => {
    const response = await workerExports.default.fetch(`${ORIGIN}/api/fx?since=last-tuesday`);
    expect(response.status).toBe(400);
  });

  it("answers an empty page rather than nothing for a month never published", async () => {
    const page = (await workerExports.default.fetch(`${ORIGIN}/api/fx?since=2026-09-30`).then((r) => r.json())) as FxPage;
    expect(page.rates).toEqual([]);
  });

  it("serves the recent end of a window too wide to fit, not the old end", async () => {
    // A device asking from six years ago must not get 2020 and an empty page:
    // its high-water mark would stay six years behind and every sync would
    // fetch the same nothing. The tail is the half it can use.
    const response = await workerExports.default.fetch(`${ORIGIN}/api/fx?since=2020-01-01`);
    const page = (await response.json()) as FxPage;

    expect(page.hasMore).toBe(true);
    expect(page.rates.some((rate) => rate.currency === "EUR")).toBe(true);
  });
});
