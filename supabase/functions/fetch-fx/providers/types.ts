/// One provider's answer for one day.
export interface FxSnapshot {
  /// The date the provider says these rates are for, YYYY-MM-DD. Not the date
  /// we asked for: ECB has no weekend publication, so asking for a Sunday
  /// legitimately returns Friday's, and the provider is the authority on which
  /// day it actually gave us.
  asOf: string;
  /// Units of each currency per one USD. Every adapter normalises to this, so
  /// nothing downstream needs to know a provider's native base.
  rates: Record<string, number>;
}

export interface FetchOptions {
  /// The date wanted, or null for the most recent publication.
  asOf: string | null;
  /// The currencies still missing. An adapter may return more; extras are
  /// ignored rather than being an error.
  currencies: string[];
  /// The provider row's `config` column.
  config: Record<string, unknown>;
}

/// A rate source.
///
/// Deliberately the entire contract. Everything provider-specific — base
/// currency, response shape, auth, date format — is absorbed by the adapter,
/// so the waterfall in index.ts has no knowledge of any particular service and
/// adding one cannot require changing it.
export interface FxProvider {
  /// Matches fx_providers.kind.
  readonly kind: string;
  /// Returns null for any failure. Adapters never throw: a provider being down
  /// is an ordinary event that the waterfall handles by moving on.
  fetch(options: FetchOptions): Promise<FxSnapshot | null>;
}

/// Shared helper: a fetch that cannot hang the run.
export async function getJson(
  url: string,
  timeoutMs = 10_000,
): Promise<unknown | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/// Narrows a provider's rate map to finite positive numbers.
///
/// A provider returning null, zero or a string for a currency should cost us
/// that one currency, not the whole response.
export function sanitise(
  raw: unknown,
  wanted: string[],
): Record<string, number> {
  const out: Record<string, number> = {};
  if (typeof raw !== 'object' || raw === null) return out;
  const map = raw as Record<string, unknown>;
  for (const code of wanted) {
    const value = map[code];
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
      out[code] = value;
    }
  }
  return out;
}
