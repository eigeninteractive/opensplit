import { readFile } from "node:fs/promises";
import path from "node:path";

import ts from "typescript";

/**
 * Refuses a deploy whose D1 or KV binding still names the committed
 * placeholder. Wrangler binds to an id without checking it exists, so such a
 * deploy succeeds, passes the health check (which touches neither), and fails
 * on the first real request. Only the top level is checked: `env.test` is
 * local-only and keeps the placeholders on purpose.
 */

interface Binding {
  binding: string;
  database_id?: string;
  id?: string;
}

const file = path.join(import.meta.dirname, "..", "wrangler.jsonc");
const { config, error } = ts.parseConfigFileTextToJson(file, await readFile(file, "utf8"));
if (error) throw new Error(ts.flattenDiagnosticMessageText(error.messageText, "\n"));

const bindings: Binding[] = [...(config.d1_databases ?? []), ...(config.kv_namespaces ?? [])];
const isPlaceholder = (id: string | undefined) => id === undefined || /^0+f?$/.test(id.replaceAll("-", ""));
const unset = bindings.filter((binding) => isPlaceholder(binding.database_id ?? binding.id)).map((binding) => binding.binding);

if (unset.length > 0) {
  console.error(`wrangler.jsonc still names placeholder resources for ${unset.join(", ")}. Create them and commit their ids; see docs/runbook.md, steps 1 and 2.`);
  process.exit(1);
}
console.log(`Deploying to real resources: ${bindings.map((binding) => binding.binding).join(", ")}.`);
