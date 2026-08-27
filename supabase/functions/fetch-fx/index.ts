// Fetches exchange rates and stores them centrally.
//
// Runs on a schedule (see the pg_cron job in the migration) and can also be
// invoked directly to backfill. Rates are display-only — nothing here can move
// money — but they are read by every member of a group, so they are fetched
// once by the server rather than independently by each device. Two phones
// showing different estimates for the same group is a support ticket nobody
// can resolve.
//
// Deploy:
//   supabase functions deploy fetch-fx
//   supabase secrets set FX_FETCH_SECRET="$(openssl rand -hex 32)"
//   # optional, enables the keyed ExchangeRate-API provider:
//   supabase secrets set EXCHANGERATE_API_KEY=...
//
// Backfill a specific day:
//   curl -H "x-fx-secret: $SECRET" -d '{"as_of":"2026-08-14"}' <function-url>
// Backfill a range, most recent first:
//   curl -H "x-fx-secret: $SECRET" -d '{"backfill_days":90}' <function-url>

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { registry } from "./providers/registry.ts";
import { FxSnapshot } from "./providers/types.ts";

interface ProviderRow {
  id: number;
  name: string;
  kind: string;
  priority: number;
  enabled: boolean;
  supports_history: boolean;
  config: Record<string, unknown>;
}

const secret = Deno.env.get("FX_FETCH_SECRET") ?? "";

/// Constant-time comparison, so the secret cannot be recovered by timing.
function secretMatches(provided: string, expected: string): boolean {
  if (provided.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < provided.length; i++) {
    diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

/// Runs providers in priority order until every currency is covered.
///
/// Deliberately not "first success wins". Coverage is the whole reason there is
/// more than one provider: ECB publishes about thirty currencies, so stopping
/// at its perfectly successful response would leave AED, KWD, LKR and the rest
/// permanently absent — which is exactly the two-tier behaviour this design
/// exists to remove. Each provider fills what the ones before it could not, and
/// every row records which provider supplied it.
async function runWaterfall(
  supabase: SupabaseClient,
  providers: ProviderRow[],
  asOf: string | null,
  allCurrencies: string[],
): Promise<{ stored: number; covered: string[]; missing: string[] }> {
  const outstanding = new Set(allCurrencies);
  let stored = 0;

  for (const row of providers) {
    if (outstanding.size === 0) break;

    // Asking a latest-only provider for a past date would get today's rates
    // labelled as that date, which is worse than having no rate at all.
    if (asOf !== null && !row.supports_history) continue;

    const provider = registry[row.kind];
    if (!provider) {
      console.warn(`no adapter for provider kind "${row.kind}" (${row.name})`);
      continue;
    }

    const attemptedAt = new Date().toISOString();
    let snapshot: FxSnapshot | null = null;
    let failure: string | null = null;

    try {
      snapshot = await provider.fetch({
        asOf,
        currencies: [...outstanding],
        config: row.config ?? {},
      });
      if (snapshot === null) failure = "no usable response";
    } catch (cause) {
      failure = String(cause);
    }

    if (snapshot) {
      const rows = Object.entries(snapshot.rates)
        .filter(([code]) => outstanding.has(code))
        .map(([code, rate]) => ({
          as_of: snapshot!.asOf,
          currency: code,
          rate,
          source: row.name,
        }));

      if (rows.length > 0) {
        const { error } = await supabase
          .from("fx_rates")
          .upsert(rows, { onConflict: "as_of,currency" });
        if (error) {
          failure = `store failed: ${error.message}`;
        } else {
          stored += rows.length;
          for (const { currency } of rows) outstanding.delete(currency);
        }
      }
    }

    await supabase
      .from("fx_providers")
      .update({
        last_attempt_at: attemptedAt,
        ...(failure === null
          ? { last_success_at: attemptedAt, last_error: null }
          : { last_error: failure }),
      })
      .eq("id", row.id);
  }

  return {
    stored,
    covered: allCurrencies.filter((c) => !outstanding.has(c)),
    missing: [...outstanding],
  };
}

Deno.serve(async (request) => {
  if (!secret) {
    console.error("FX_FETCH_SECRET is not set; refusing to run");
    return new Response("misconfigured", { status: 500 });
  }
  if (!secretMatches(request.headers.get("x-fx-secret") ?? "", secret)) {
    return new Response("forbidden", { status: 403 });
  }

  const body = await request.json().catch(() => ({}));
  const asOf: string | null = typeof body.as_of === "string"
    ? body.as_of
    : null;
  const backfillDays: number = Number.isInteger(body.backfill_days)
    ? Math.min(body.backfill_days, 400)
    : 0;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Only currencies the app can actually format. This is what makes "supported"
  // one question rather than one per provider.
  const { data: currencyRows, error: currencyError } = await supabase
    .from("currencies")
    .select("code");
  if (currencyError || !currencyRows?.length) {
    console.error("could not read currencies", currencyError);
    return new Response("error", { status: 500 });
  }
  const currencies = currencyRows.map((r: { code: string }) => r.code.trim());

  const { data: providerRows, error: providerError } = await supabase
    .from("fx_providers")
    .select("*")
    .eq("enabled", true)
    .order("priority", { ascending: true });
  if (providerError) {
    console.error("could not read providers", providerError);
    return new Response("error", { status: 500 });
  }
  const providers = (providerRows ?? []) as ProviderRow[];

  // A backfill walks backwards from yesterday; a normal run asks for latest.
  const targets: (string | null)[] = backfillDays > 0
    ? Array.from({ length: backfillDays }, (_, i) => {
      const d = new Date();
      d.setUTCDate(d.getUTCDate() - (i + 1));
      return d.toISOString().slice(0, 10);
    })
    : [asOf];

  const report: Record<string, unknown>[] = [];
  for (const target of targets) {
    // Skip a day that is already complete, so a repeated backfill is cheap and
    // a provider's quota is not spent re-fetching what we hold.
    const wanted = target === null
      ? currencies
      : await missingFor(supabase, currencies, target);
    if (wanted.length === 0) continue;

    const result = await runWaterfall(supabase, providers, target, wanted);
    report.push({ as_of: target ?? "latest", ...result });
  }

  return Response.json({ ok: true, runs: report });
});

/// Currencies with no rate published on or before [asOf].
///
/// "On or before" rather than "on", because ECB does not publish at weekends
/// and a Friday rate is the correct answer for a Sunday. Treating a Sunday as a
/// gap would make every backfill chase rates that will never exist.
///
/// Goes through an RPC rather than selecting the fx_rates rows and collecting
/// the distinct currencies here. That reads as the obvious thing and is wrong:
/// PostgREST caps a response at `max_rows` (1000), sixteen currencies over a
/// couple of years is well past it, and the silently dropped tail makes
/// currencies look unpriced. The fetcher then spends requests — against a
/// 1,500-a-month free tier — re-fetching rates it already holds. One row per
/// currency, computed where the rows are, has nothing to truncate.
async function missingFor(
  supabase: SupabaseClient,
  currencies: string[],
  asOf: string,
): Promise<string[]> {
  const { data, error } = await supabase.rpc("fx_currencies_covered", {
    p_as_of: asOf,
  });
  if (error) {
    // Better to fetch a day we already hold than to skip one we do not: the
    // waterfall is idempotent, and an upsert of an identical rate costs a row
    // write. Treating the whole day as missing is the safe direction.
    console.error("fx_currencies_covered failed", error);
    return currencies;
  }

  const held = new Set(
    (data ?? []).map((r: { currency: string }) => r.currency.trim()),
  );
  return currencies.filter((c) => !held.has(c));
}
