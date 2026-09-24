import type { FxRate } from "../schemas/reference";

/**
 * A month of rates, as KV holds it.
 *
 * Its own module, with no runtime imports, because both ends need it and one of
 * them must not reach `cloudflare:workers`: the `Fx` object writes these, the
 * `/api/fx` route reads them, and `scripts/write-openapi.ts` imports that route
 * under plain Node to emit the committed contract. A shape shared by a Durable
 * Object and a plain handler has to live where neither drags the other in.
 *
 * A flat array rather than a map of day to map of currency. Sixteen currencies
 * over thirty-one days is about five hundred rows and thirty kilobytes either
 * way, and the flat shape is the one the client already wants — it writes these
 * straight into its own `fx_rates` — so nothing has to be turned inside out at
 * either end.
 */
export interface MonthBlob {
  month: string;
  rates: FxRate[];
}

export const monthKey = (month: string) => `fx:${month}`;
