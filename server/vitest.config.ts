import path from "node:path";

import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { exportJWK, generateKeyPair } from "jose";
import { defineConfig } from "vitest/config";

/** Tests run in workerd against real Durable Objects, D1 and KV, with bindings from wrangler.jsonc. */

// The same migrations `wrangler d1 migrations apply` runs.
const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));

/** A stand-in for Google's signing key: tokens are signed and verified for real, against this. */
const KEY_ID = "test-key";
const { publicKey, privateKey } = await generateKeyPair("RS256", {
  extractable: true,
});
const publicJwk = {
  ...(await exportJWK(publicKey)),
  kid: KEY_ID,
  alg: "RS256",
  use: "sig",
};
const privateJwk = {
  ...(await exportJWK(privateKey)),
  kid: KEY_ID,
  alg: "RS256",
};

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        // Per-file storage, so no suite sees another's rows.
        isolatedStorage: true,

        // Three stand-in pages for the three branches of the asset fallback. Restates the deployed
        // `binding` and `run_worker_first`, because this block replaces wrangler.jsonc's.
        assets: {
          directory: path.join(import.meta.dirname, "test/fixtures/assets"),
          binding: "ASSETS",
          run_worker_first: ["/api/*"],
        },

        // Every outbound request fails unless answered here.
        outboundService: (request: Request) => {
          const url = new URL(request.url);
          if (url.hostname === "www.googleapis.com" && url.pathname === "/oauth2/v3/certs") {
            return Response.json({ keys: [publicJwk] });
          }
          return new Response(`Refusing an un-mocked outbound request to ${url.href}`, { status: 502 });
        },

        bindings: {
          TEST_MIGRATIONS: migrations,
          TEST_GOOGLE_PRIVATE_JWK: privateJwk,

          APP_ORIGIN: "http://localhost:8787",

          // Real-shaped secrets, so tests take production's code paths.
          BETTER_AUTH_SECRET: "test-secret-that-is-long-enough-to-not-warn",
          GOOGLE_CLIENT_ID: "test-google-client-id.apps.googleusercontent.com",
          GOOGLE_CLIENT_SECRET: "test-google-client-secret",
          RESEND_API_KEY: "",
          FCM_PROJECT_ID: "",
          FCM_SERVICE_ACCOUNT: "",
        },
      },
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
