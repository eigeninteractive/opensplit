import { FetchOptions, FxProvider, FxSnapshot, getJson, sanitise } from './types.ts';

/// ECB reference rates, republished by Frankfurter.
///
/// First in the waterfall because it is an official published source, and
/// because it is the only free one that answers for a past date. Its coverage
/// is the ~30 ECB reference currencies, so it routinely returns a partial
/// answer — which is expected, not a failure.
export const frankfurter: FxProvider = {
  kind: 'frankfurter',

  async fetch({ asOf, currencies, config }: FetchOptions): Promise<FxSnapshot | null> {
    const baseUrl = (config.base_url as string) ?? 'https://api.frankfurter.dev';
    // USD as the base so the response is already in pivot units and no
    // arithmetic happens here.
    const symbols = currencies.filter((c) => c !== 'USD');
    if (symbols.length === 0) return null;

    const path = asOf ?? 'latest';
    const url = `${baseUrl}/v1/${path}?base=USD&symbols=${symbols.join(',')}`;

    const body = await getJson(url);
    if (typeof body !== 'object' || body === null) return null;

    const { date, rates } = body as { date?: unknown; rates?: unknown };
    if (typeof date !== 'string') return null;

    const clean = sanitise(rates, symbols);
    if (Object.keys(clean).length === 0) return null;

    // USD against itself, so the pivot has no gap and no special case.
    clean.USD = 1;
    return { asOf: date, rates: clean };
  },
};
