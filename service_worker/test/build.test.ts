import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, test } from "node:test";

import { buildServiceWorker, firebaseConfig } from "../build.ts";

const FIREBASE = { apiKey: "test-api-key", appId: "test-app-id", messagingSenderId: "123", projectId: "test-project" };

let root: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "opensplit-sw-"));
  for (const path of [
    "app/index.html",
    "app/flutter_bootstrap.js",
    "app/main.dart.js",
    "app/main.dart.wasm",
    "app/sqlite3.wasm",
    "app/drift_worker.js",
    "app/canvaskit/canvaskit.wasm",
    "app/canvaskit/canvaskit.js.symbols",
    "app/flutter_service_worker.js",
    "icons/Icon-192.png",
    "favicon.svg",
    "index.html",
    "terms/index.html",
  ]) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), path);
  }
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

const worker = () => readFileSync(join(root, "app/sw.js"), "utf8");

test("the precache is the whole client and its icons, and nothing of the static site", async () => {
  await buildServiceWorker(root, FIREBASE);

  for (const url of ["/app/index.html", "/app/main.dart.js", "/app/main.dart.wasm", "/app/sqlite3.wasm", "/app/drift_worker.js", "/app/canvaskit/canvaskit.wasm", "/icons/Icon-192.png", "/favicon.svg"]) {
    assert.ok(worker().includes(`"${url}"`), url);
  }
  for (const url of ['"/index.html"', "/terms/", ".symbols", "flutter_service_worker.js"]) {
    assert.ok(!worker().includes(url), url);
  }
});

test("the worker is one finished script, with nothing left for the build to fill in", async () => {
  await buildServiceWorker(root, FIREBASE);

  for (const placeholder of ["__WB_MANIFEST", "__FIREBASE_CONFIG__", "process.env.NODE_ENV", "import "]) {
    assert.ok(!worker().includes(placeholder), placeholder);
  }
});

test("push is configured only when every identifier is", async () => {
  const config = { WEB_FCM_API_KEY: "test-api-key", WEB_FCM_APP_ID: "test-app-id", FCM_SENDER_ID: "123", FCM_PROJECT_ID: "test-project" };
  assert.deepEqual(firebaseConfig(config), FIREBASE);
  assert.equal(firebaseConfig({ ...config, WEB_FCM_API_KEY: "" }), null);

  await buildServiceWorker(root, null);
  assert.ok(!worker().includes("test-api-key"));
  await buildServiceWorker(root, FIREBASE);
  assert.ok(worker().includes("test-api-key"));
});

test("a client missing a file it cannot start without is not packaged as offline capable", async () => {
  rmSync(join(root, "app/sqlite3.wasm"));

  await assert.rejects(buildServiceWorker(root, FIREBASE), /missing sqlite3\.wasm/);
});
