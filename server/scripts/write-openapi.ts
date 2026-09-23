import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

import { app } from "../src/app";
import { openApiDocument } from "../src/openapi";

/**
 * Writes the committed copy of the contract.
 *
 * The same document the Worker serves at `/api/openapi.json`, written to disk
 * so that a change to the wire format shows up in review as a change to the
 * spec — and so the Dart client has something pinned to generate from. CI runs
 * this and fails on a diff, exactly as it already does for `drift_schemas/`.
 */
const spec = app.getOpenAPIDocument(openApiDocument);

const out = path.join(import.meta.dirname, "..", "..", "docs", "openapi.json");
await mkdir(path.dirname(out), { recursive: true });
await writeFile(out, `${JSON.stringify(spec, null, 2)}\n`);
console.log(`wrote ${out}`);
