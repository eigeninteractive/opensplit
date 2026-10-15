import { apiBasePath } from "./paths";

/**
 * The document's metadata, shared by the served `/api/openapi.json` and the
 * committed `docs/openapi.json`. OpenAPI 3.0.3: Dart generators handle 3.1 unevenly.
 */
export const openApiDocument = {
  openapi: "3.0.3",
  servers: [{ url: apiBasePath }],
  info: {
    version: "1.0.0",
    title: "OpenSplit",
    description: "The server stores financial history and enforces membership, settlement and write concurrency rules. Splitting, debt simplification and analytics happen on the device.",
  },
};
