/**
 * The document's own metadata, in one place.
 *
 * Shared by the Worker, which serves it at `/api/openapi.json`, and by
 * `scripts/write-openapi.ts`, which writes the committed copy. Two definitions
 * would differ by a version string one day and produce a spurious CI failure.
 *
 * Emitted as OpenAPI **3.0.3** rather than 3.1: nothing here needs 3.1, and
 * support for it across Dart client generators is uneven.
 */
export const openApiDocument = {
  openapi: "3.0.3",
  info: {
    version: "1.0.0",
    title: "OpenSplit",
    description: "The server stores rows and enforces one invariant. It computes nothing: splitting, folding balances, simplifying debts and analytics all happen on the device.",
  },
} as const;
