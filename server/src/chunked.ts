/**
 * D1 and Durable Object SQLite bind at most 100 values a statement. Every
 * value a query sends is one: each column of each row in an insert, each id in
 * an `IN (…)` list, each value put into a `sql` template.
 */
export const MAX_BOUND_VALUES = 100;

/** A list in pieces no longer than [size]. The default leaves room for a few other values in the same `IN (…)` query. */
export function chunked<T>(items: readonly T[], size = 90): T[][] {
  const chunks: T[][] = [];
  for (let start = 0; start < items.length; start += size) chunks.push(items.slice(start, start + size));
  return chunks;
}

/**
 * Rows for a multi-row insert, in pieces that each fit one statement: as many
 * rows as the limit allows at this many columns a row. Inside a Durable Object
 * the pieces run in the same transaction and the same process, so splitting
 * costs nothing.
 */
export function insertable<T extends object>(rows: readonly T[]): T[][] {
  const columns = Math.max(1, ...rows.map((row) => Object.keys(row).length));
  return chunked(rows, Math.floor(MAX_BOUND_VALUES / columns));
}
