import { FetchOptions, FxProvider, FxSnapshot, getJson, sanitise } from './types.ts';

/// ExchangeRate-API's open endpoint: no key, no historical.
///
/// Its job in the waterfall is coverage. It carries about 166 currencies,
/// including AED, KWD, BHD, LKR, NPR and VND — the ones ECB does not publish
/// and which between them account for most of where this app is aimed.
export const exchangerateOpen: FxProvider = {
  kind: 'exchangerate_open',

  async fetch({ asOf, currencies, config }: FetchOptions): Promise<FxSnapshot | null> {
    // Latest only. Asked for a past date it would answer with today's rates,
    // which is precisely the wrong answer — so it declines instead.
    if (asOf !== null) return null;

    const baseUrl = (config.base_url as string) ?? 'https://open.er-api.com';
    const body = await getJson(`${baseUrl}/v6/latest/USD`);
    if (typeof body !== 'object' || body === null) return null;

    const { result, rates, time_last_update_utc } = body as {
      result?: unknown;
      rates?: unknown;
      time_last_update_utc?: unknown;
    };
    if (result !== 'success') return null;

    const clean = sanitise(rates, currencies);
    if (Object.keys(clean).length === 0) return null;

    return { asOf: toIsoDate(time_last_update_utc), rates: clean };
  },
};

/// The provider stamps an RFC 1123 time; we store a date.
function toIsoDate(value: unknown): string {
  const parsed = typeof value === 'string' ? new Date(value) : new Date();
  const date = Number.isNaN(parsed.getTime()) ? new Date() : parsed;
  return date.toISOString().slice(0, 10);
}
