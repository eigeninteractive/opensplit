import categories from "./data/categories.json";
import currencies from "./data/currencies.json";
import { type Reference, ReferenceSchema } from "./schemas/reference";

/**
 * Currencies and categories, bundled with the code rather than stored.
 * Category ids are written onto entries, so they never change, and rows are
 * only ever added: the client merges with an upsert and never deletes.
 */
export const reference: Reference = ReferenceSchema.parse({ currencies, categories });

/** FNV-1a of the content, so the ETag changes whenever the JSON does. */
function fingerprint(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export const referenceEtag = `"${fingerprint(JSON.stringify(reference))}"`;

export const supportedCurrencies: string[] = reference.currencies.map((currency) => currency.code);
