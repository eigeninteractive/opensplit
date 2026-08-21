import { FetchOptions, FxProvider, FxSnapshot, getJson, sanitise } from './types.ts';

/// ExchangeRate-API's keyed v6 API.
///
/// The free key covers `latest` at 1,500 requests a month, which against a
/// daily cron is roughly fifty times more than this needs. Historical is a paid
/// feature, so whether this provider participates in a backfill is the
/// `supports_history` flag on its row rather than anything in this file: buying
/// the plan is then a one-column change, not a deploy.
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
    const url = asOf === null
      ? `${baseUrl}/v6/${key}/latest/USD`
      // history/{base}/{y}/{m}/{d} — 403s on the free plan, which the waterfall
      // treats as this provider simply having nothing to offer.
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
