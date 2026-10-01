/** D1 and Durable Object SQLite bind at most 100 parameters per statement, so lists go in chunks below that. */
export function chunked<T>(items: readonly T[], size = 90): T[][] {
  const chunks: T[][] = [];
  for (let start = 0; start < items.length; start += size) chunks.push(items.slice(start, start + size));
  return chunks;
}
