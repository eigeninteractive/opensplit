import { exchangerateV6 } from "./exchangerate_v6.ts";
import { frankfurter } from "./frankfurter.ts";
import { FxProvider } from "./types.ts";

/// Every adapter the function knows how to run, keyed by fx_providers.kind.
///
/// Adding a source is one file plus one row in fx_providers, and the row can be
/// inserted, reordered or disabled without a deploy. A row naming a kind that
/// is not here is skipped with a warning rather than failing the run, so
/// configuration may safely run ahead of the code.
export const registry: Record<string, FxProvider> = {
  [frankfurter.kind]: frankfurter,
  [exchangerateV6.kind]: exchangerateV6,
};
