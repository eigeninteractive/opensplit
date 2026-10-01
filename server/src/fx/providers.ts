/**
 * Where exchange rates come from: a waterfall, because ECB covers about thirty
 * currencies and each later provider fills what the earlier ones could not.
 * Code rather than a table, since nothing would edit such a table without a
 * deploy anyway; `provider_health` records why a currency is missing.
 */

/** One provider's answer for one day. */
export interface FxSnapshot {
  /** The day the provider says it answered for (ECB gives Friday for a Sunday). */
  asOf: string;

  /** Units of each currency per one USD, whatever the provider's native base. */
  rates: Record<string, number>;
}

export interface FetchOptions {
  /** Null for the most recent publication. */
  asOf: string | null;

  /** The currencies still missing; extras in an answer are ignored. */
  currencies: string[];

  env: Env;
}

/** A rate source; everything provider-specific stays inside the adapter. */
export interface FxProvider {
  readonly name: string;

  /** Whether it can answer for a past date; the waterfall skips it otherwise. */
  readonly supportsHistory: boolean;

  /** Null for any failure: a provider being down is ordinary. */
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

/** Keeps finite positive numbers, so one bad value costs one currency, not the response. */
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

/** ECB reference rates via Frankfurter: official, free, and the one that answers for past dates. */
export const frankfurter: FxProvider = {
  name: "frankfurter",
  supportsHistory: true,

  async fetch({ asOf, currencies }: FetchOptions): Promise<FxSnapshot | null> {
    // USD as the base, so the answer is already in pivot units.
    const symbols = currencies.filter((code) => code !== "USD");
    if (symbols.length === 0) return null;

    const body = await getJson(`https://api.frankfurter.dev/v1/${asOf ?? "latest"}?base=USD&symbols=${symbols.join(",")}`);
    if (typeof body !== "object" || body === null) return null;

    const { date, rates } = body as { date?: unknown; rates?: unknown };
    if (typeof date !== "string") return null;

    const clean = sanitise(rates, symbols);
    if (Object.keys(clean).length === 0) return null;

    clean.USD = 1;
    return { asOf: date, rates: clean };
  },
};

/**
 * ExchangeRate-API v6: all 166 currencies, so coverage is uniform. Latest only
 * (history needs a paid plan), and skipped when no key is configured.
 */
export const exchangerateV6: FxProvider = {
  name: "exchangerate_v6",
  supportsHistory: false,

  async fetch({ asOf, currencies, env }: FetchOptions): Promise<FxSnapshot | null> {
    const key = env.EXCHANGERATE_API_KEY;
    if (!key) return null;

    const url = asOf === null ? `https://v6.exchangerate-api.com/v6/${key}/latest/USD` : `https://v6.exchangerate-api.com/v6/${key}/history/USD/${asOf.replaceAll("-", "/")}`;

    const body = await getJson(url);
    if (typeof body !== "object" || body === null) return null;

    const payload = body as Record<string, unknown>;
    if (payload.result !== "success") return null;

    // `conversion_rates` on latest, `rates` on history.
    const clean = sanitise(payload.conversion_rates ?? payload.rates, currencies);
    if (Object.keys(clean).length === 0) return null;

    return { asOf: asOf ?? isoFromUnix(payload.time_last_update_unix), rates: clean };
  },
};

function isoFromUnix(value: unknown): string {
  const seconds = typeof value === "number" ? value : Date.now() / 1000;
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}

/** The waterfall, in order. */
export const providers: FxProvider[] = [frankfurter, exchangerateV6];
