/**
 * Builds /app/sw.js into a finished web bundle: Workbox's precache manifest of
 * the release, the worker's source and its dependencies, bundled into one
 * classic script. tool/build_web.dart runs this after `flutter build web`.
 *
 *   node build.ts --root=../build/web --config=../env/app.json
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

import { build } from "esbuild";
import { getManifest } from "workbox-build";

/** The files a release cannot start without; a bundle missing one is not offline-capable. */
const REQUIRED = ["index.html", "flutter_bootstrap.js", "main.dart.js", "sqlite3.wasm", "drift_worker.js"];

/** Workbox's default is 2 MB and skips anything larger with only a warning; Flutter's renderers are several times that. */
const MAXIMUM_FILE_SIZE = 16 * 1024 * 1024;

export interface FirebaseConfig {
  apiKey: string;
  appId: string;
  messagingSenderId: string;
  projectId: string;
}

/** The web app's Firebase identifiers from the build configuration, or null when push is not configured, as lib/config.dart decides it. */
export function firebaseConfig(config: Record<string, unknown>): FirebaseConfig | null {
  const value = (key: string) => (typeof config[key] === "string" ? config[key] : "");
  const firebase = {
    apiKey: value("WEB_FCM_API_KEY"),
    appId: value("WEB_FCM_APP_ID"),
    messagingSenderId: value("FCM_SENDER_ID"),
    projectId: value("FCM_PROJECT_ID"),
  };
  return Object.values(firebase).every(Boolean) ? firebase : null;
}

/** Writes `<root>/app/sw.js` and returns how much it precaches. */
export async function buildServiceWorker(root: string, firebase: FirebaseConfig | null): Promise<{ count: number; size: number }> {
  const { manifestEntries, count, size, warnings } = await getManifest({
    globDirectory: root,
    // The client, and the root icons its document and manifest name. Never the
    // static site beside it, which has no business in the app's cache.
    globPatterns: ["app/**/*", "favicon.{png,svg}", "icons/*"],
    globIgnores: [
      "app/sw.js",
      // Flutter's deprecated worker, which flutter_bootstrap.js never registers.
      "app/flutter_service_worker.js",
      // Debug symbols, which only a person reading a stack trace ever fetches.
      "**/*.symbols",
      "**/*.map",
    ],
    maximumFileSizeToCacheInBytes: MAXIMUM_FILE_SIZE,
    // Absolute, because the client and the root icons sit at different depths
    // under the worker's /app/ location.
    manifestTransforms: [(entries) => ({ manifest: entries.map((entry) => ({ ...entry, url: `/${entry.url}` })), warnings: [] })],
  });
  if (warnings.length > 0) throw new Error(`Precache manifest: ${warnings.join("; ")}`);

  const urls = new Set(manifestEntries?.map((entry) => (typeof entry === "string" ? entry : entry.url)));
  const missing = REQUIRED.filter((file) => !urls.has(`/app/${file}`));
  if (missing.length > 0) throw new Error(`Incomplete Flutter bundle: missing ${missing.join(", ")}`);

  await build({
    entryPoints: [fileURLToPath(new URL("src/sw.ts", import.meta.url))],
    outfile: `${root}/app/sw.js`,
    bundle: true,
    format: "iife",
    target: "es2022",
    minify: true,
    logLevel: "warning",
    define: {
      "self.__WB_MANIFEST": JSON.stringify(manifestEntries),
      __FIREBASE_CONFIG__: JSON.stringify(firebase),
      // Workbox's development logging, compiled out.
      "process.env.NODE_ENV": JSON.stringify("production"),
    },
  });
  return { count, size };
}

if (import.meta.main) {
  const { values } = parseArgs({ options: { root: { type: "string" }, config: { type: "string" } } });
  if (!values.root || !values.config) throw new Error("Usage: node build.ts --root=<bundle> --config=<app.json>");

  const config = JSON.parse(readFileSync(values.config, "utf8")) as Record<string, unknown>;
  const firebase = firebaseConfig(config);
  const { count, size } = await buildServiceWorker(values.root, firebase);
  console.log(`sw.js precaches ${count} files (${(size / 1e6).toFixed(1)} MB); push ${firebase ? "on" : "off"}.`);
}
