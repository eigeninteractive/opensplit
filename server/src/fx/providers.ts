/**
 * Where exchange rates come from.
 *
 * Rates are display-only — nothing here can move money — but they are read by
 * every member of a group, so they are fetched once by the server rather than
 * independently by each device. Two phones showing different estimates for the
 * same group is a support ticket nobody can resolve.
 *
 * ## Why there is a waterfall rather than a provider
 *
 * Coverage. ECB publishes about thirty currencies, so stopping at its perfectly
 * successful response would leave AED, KWD, LKR, NPR, VND and BHD permanently
 * absent — which is exactly the two-tier behaviour this design exists to
 * remove. Each provider fills what the ones before it could not, and every rate
 * records which one supplied it.
 *
 * ## Why the registry is code and not a table
 *
 * In Postgres it was `fx_providers`: rows that could be reordered, disabled or
 * reconfigured without a deploy. That flexibility bought nothing — there was no
 * interface to edit them with, so every change was a migration anyway — and it
 * cost a table, a trigger and a `SECURITY DEFINER` read from an edge function.
 * Here the order is an array, a provider with no key configured skips itself,
 * and changing either is a diff somebody reviews.
 *
 * What was worth keeping is the health record: the object stores each
 * provider's last attempt, last success and last error, because "why is AED
 * missing" is otherwise unanswerable.
 */

/** One provider's answer for one day. */
export interface FxSnapshot {
  /**
   * The date the provider says these rates are for, `YYYY-MM-DD`.
   *
   * Not the date we asked for. ECB has no weekend publication, so asking for a
   * Sunday legitimately returns Friday's, and the provider is the authority on
   * which day it actually gave us — labelling Friday's rates as Sunday's would
   * be inventing data.
   */
  asOf: string;

  /**
   * Units of each currency per one USD.
   *
   * Every adapter normalises to this, so nothing downstream needs to know a
   * provider's native base.
   */
  rates: Record<string, number>;
}

export interface FetchOptions {
  /** The date wanted, or null for the most recent publication. */
  asOf: string | null;

  /**
   * The currencies still missing.
   *
   * An adapter may return more; extras are ignored rather than being an error.
   */
  currencies: string[];

  /** The Worker's environment, for adapters that need a key. */
  env: Env;
}

/**
 * A rate source.
 *
 * Deliberately the entire contract. Everything provider-specific — base
 * currency, response shape, auth, date format — is absorbed by the adapter, so
 * the waterfall has no knowledge of any particular service and adding one
 * cannot require changing it.
 */
export interface FxProvider {
  readonly name: string;

  /**
   * Whether this provider can answer for a past date.
   *
   * Asking a latest-only provider for one would get today's rates labelled as
   * that date, which is worse than having no rate at all — so the waterfall
   * skips it rather than the adapter having to refuse.
   */
  readonly supportsHistory: boolean;

  /**
   * Returns null for any failure.
   *
   * Adapters never throw: a provider being down is an ordinary event that the
   * waterfall handles by moving on to the next one.
   */
  fetch(options: FetchOptions): Promise<FxSnapshot | null>;
}

/** A fetch that cannot hang the run. */
async function getJson(url: string, timeoutMs = 10_000): Promise<unknown | null> {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

/**
 * Narrows a provider's rate map to finite positive numbers.
 *
 * A provider returning null, zero or a string for one currency should cost us
 * that currency, not the whole response.
 */
function sanitise(raw: unknown, wanted: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  if (typeof raw !== "object" || raw === null) return out;

  const map = raw as Record<string, unknown>;
  for (const code of wanted) {
    const value = map[code];
    if (typeof value === "number" && Number.isFinite(value) && value > 0) {
      out[code] = value;
    }
  }
  return out;
}

/**
 * ECB reference rates, republished by Frankfurter.
 *
 * First in the waterfall because it is an official published source, and
 * because it is the only free one that answers for a past date. Its coverage is
 * the ~30 ECB reference currencies, so it routinely returns a partial answer —
 * which is expected, not a failure.
 */
export const frankfurter: FxProvider = {
  name: "frankfurter",
  supportsHistory: true,

  async fetch({ asOf, currencies }: FetchOptions): Promise<FxSnapshot | null> {
    // USD as the base so the response is already in pivot units and no
    // arithmetic happens here.
    const symbols = currencies.filter((code) => code !== "USD");
    if (symbols.length === 0) return null;

    const body = await getJson(`https://api.frankfurter.dev/v1/${asOf ?? "latest"}?base=USD&symbols=${symbols.join(",")}`);
    if (typeof body !== "object" || body === null) return null;

    const { date, rates } = body as { date?: unknown; rates?: unknown };
    if (typeof date !== "string") return null;

    const clean = sanitise(rates, symbols);
    if (Object.keys(clean).length === 0) return null;

    // USD against itself, so the pivot has no gap and no special case.
    clean.USD = 1;
    return { asOf: date, rates: clean };
  },
};

/**
 * ExchangeRate-API's keyed v6 API.
 *
 * Carries 166 currencies — every one this app supports, including the AED, KWD,
 * BHD, LKR, NPR and VND that ECB does not publish. This is what makes coverage
 * uniform rather than two-tier.
 *
 * Latest only. The historical endpoint answers `plan-upgrade-required` on the
 * free plan — verified against the live API, not just the docs — so it declares
 * no history support and the waterfall skips it when filling a past date.
 * Frankfurter covers history, free and without a key.
 *
 * With no key configured it returns null immediately, which is how a
 * self-hosted deployment runs on Frankfurter alone without editing anything.
 */
export const exchangerateV6: FxProvider = {
  name: "exchangerate_v6",
  supportsHistory: false,

  async fetch({ asOf, currencies, env }: FetchOptions): Promise<FxSnapshot | null> {
    const key = env.EXCHANGERATE_API_KEY;
    if (!key) return null;

    // Never asked for a past date in practice, because `supportsHistory` says
    // it cannot serve one. Kept correct rather than throwing, so the flag stays
    // the single place that decides.
    const url = asOf === null ? `https://v6.exchangerate-api.com/v6/${key}/latest/USD` : `https://v6.exchangerate-api.com/v6/${key}/history/USD/${asOf.replaceAll("-", "/")}`;

    const body = await getJson(url);
    if (typeof body !== "object" || body === null) return null;

    const payload = body as Record<string, unknown>;
    if (payload.result !== "success") return null;

    // The latest endpoint calls it conversion_rates; older docs for history use
    // rates. Accept either rather than depending on which.
    const clean = sanitise(payload.conversion_rates ?? payload.rates, currencies);
    if (Object.keys(clean).length === 0) return null;

    return { asOf: asOf ?? isoFromUnix(payload.time_last_update_unix), rates: clean };
  },
};

function isoFromUnix(value: unknown): string {
  const seconds = typeof value === "number" ? value : Date.now() / 1000;
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}

/**
 * The waterfall, in order.
 *
 * Frankfurter first because it is official, free, and answers for past dates;
 * ExchangeRate-API second because it fills the two dozen currencies ECB does
 * not publish. Adding a source is one object above and one entry here.
 */
export const providers: FxProvider[] = [frankfurter, exchangerateV6];
