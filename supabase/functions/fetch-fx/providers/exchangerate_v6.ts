import { FetchOptions, FxProvider, FxSnapshot, getJson, sanitise } from './types.ts';

/// ExchangeRate-API's keyed v6 API.
///
/// Carries 166 currencies — every one this app supports, including the AED,
/// KWD, BHD, LKR, NPR and VND that ECB does not publish. This is what makes
/// coverage uniform rather than two-tier.
///
/// Latest only. The historical endpoint answers `plan-upgrade-required` on the
/// free plan (verified against the live API, not just the docs), so its row
/// carries supports_history = false and the waterfall skips it when filling a
/// past date. Frankfurter covers history, free and without a key.
///
/// The key is read from an environment secret named by the provider config, so
/// it lives in Supabase secrets rather than in a table anyone with database
/// access can read.
export const exchangerateV6: FxProvider = {
  kind: 'exchangerate_v6',

  async fetch({ asOf, currencies, config }: FetchOptions): Promise<FxSnapshot | null> {
    const envName = (config.api_key_env as string) ?? 'EXCHANGERATE_API_KEY';
    const key = Deno.env.get(envName);
    if (!key) return null;

    const baseUrl = (config.base_url as string) ?? 'https://v6.exchangerate-api.com';
    // Never asked for a past date in practice, because the provider row says it
    // cannot serve one. Kept correct rather than throwing, so the flag stays
    // the single place that decides.
    const url = asOf === null
      ? `${baseUrl}/v6/${key}/latest/USD`
      : `${baseUrl}/v6/${key}/history/USD/${asOf.replaceAll('-', '/')}`;

    const body = await getJson(url);
    if (typeof body !== 'object' || body === null) return null;

    const payload = body as Record<string, unknown>;
    if (payload.result !== 'success') return null;

    // The latest endpoint calls it conversion_rates; history calls it
    // conversion_rates too, but older docs use rates. Accept either.
    const clean = sanitise(
      payload.conversion_rates ?? payload.rates,
      currencies,
    );
    if (Object.keys(clean).length === 0) return null;

    return { asOf: asOf ?? isoFromUnix(payload.time_last_update_unix), rates: clean };
  },
};

function isoFromUnix(value: unknown): string {
  const seconds = typeof value === 'number' ? value : Date.now() / 1000;
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}
