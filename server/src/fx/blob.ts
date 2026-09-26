import type { FxRate } from "../schemas/reference";

/**
 * A month of rates as KV holds it: written by the `Fx` object, read by `/api/fx`.
 * Free of runtime imports so the route can load under Node to emit the contract.
 */
export interface MonthBlob {
  month: string;
  rates: FxRate[];
}

export const monthKey = (month: string) => `fx:${month}`;
