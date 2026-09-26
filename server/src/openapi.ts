/**
 * The document's metadata, shared by the served `/api/openapi.json` and the
 * committed `docs/openapi.json`. OpenAPI 3.0.3: Dart generators handle 3.1 unevenly.
 */
export const openApiDocument = {
  openapi: "3.0.3",
  info: {
    version: "1.0.0",
    title: "OpenSplit",
    description: "The server stores rows and enforces one invariant. It computes nothing: splitting, folding balances, simplifying debts and analytics all happen on the device.",
  },
} as const;
