import categories from "./data/categories.json";
import currencies from "./data/currencies.json";
import type { Category, Currency, Reference } from "./schemas/reference";

/**
 * Currencies and categories, bundled rather than stored.
 *
 * A couple of dozen rows between them, identical for every user, changing about
 * never. In Postgres they were two tables with `using (true)` policies — which
 * is the database saying, at some length, that they are not really data. Here
 * they are two JSON files imported into the Worker bundle, which makes them
 * reviewable in a diff, deployed atomically with the code that reads them, and
 * free to serve: answering `/api/reference` touches nothing.
 *
 * ## The ids are load-bearing
 *
 * A category id is written onto entries. Changing one orphans every expense
 * that used it, on every device that has already synced, with no way to notice
 * except that a category stops rendering. They were minted once, for the
 * Postgres migration, and they are carried here unchanged for that reason
 * rather than out of sentiment.
 *
 * ## Growing, never shrinking
 *
 * A currency or category withdrawn here is still on the entries that used it,
 * and the client's merge is an upsert with no delete for exactly that reason.
 * Removing a row would break a foreign key on somebody's device to make a
 * picker tidier.
 */

/**
 * The version that changes when the content does.
 *
 * Hashing the content rather than naming a number, so the ETag cannot be
 * forgotten in the same commit that edits the JSON — which is the only failure
 * this has: a stale cache that nothing invalidates, on a response deliberately
 * cached for a day.
 *
 * FNV-1a over the serialized payload. Not a cryptographic hash and not trying
 * to be: this answers "did the bytes change", and an attacker who can change
 * the bundle has already won.
 */
function fingerprint(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export const reference: Reference = {
  currencies: currencies as Currency[],
  categories: categories as Category[],
};

export const referenceEtag = `"${fingerprint(JSON.stringify(reference))}"`;

/**
 * Every currency the app can format, which is what makes "supported" one
 * question rather than one per rate provider.
 *
 * The exchange-rate waterfall asks for exactly this set: a rate for a currency
 * no screen can render is a row nobody will ever read, and a currency with no
 * rate is the two-tier behaviour the waterfall exists to remove.
 */
export const supportedCurrencies: string[] = reference.currencies.map((currency) => currency.code);
