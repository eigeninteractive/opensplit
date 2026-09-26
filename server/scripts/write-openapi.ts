import { writeFile } from "node:fs/promises";
import path from "node:path";

import { app } from "../src/app";
import { openApiDocument } from "../src/openapi";

/** Writes the committed contract, which CI diffs and the Dart client is generated from. */
const out = path.join(import.meta.dirname, "..", "..", "docs", "openapi.json");
await writeFile(out, `${JSON.stringify(app.getOpenAPIDocument(openApiDocument), null, 2)}\n`);
console.log(`wrote ${out}`);
