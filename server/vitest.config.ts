import path from "node:path";

import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { exportJWK, generateKeyPair } from "jose";
import { defineConfig } from "vitest/config";

/**
 * Tests run inside workerd, against real Durable Objects, a real D1 and a real
 * KV — the same Miniflare `wrangler dev` uses — rather than against mocks.
 *
 * That is what makes this a fair replacement for the pgTAP suite it inherits.
 * Those tests ran against a real Postgres, and a test double for a Durable
 * Object would not have caught any of the things they were written to catch.
 *
 * Bindings come from wrangler.jsonc, so a binding that works here is a binding
 * that is actually configured, rather than one a test file invented.
 */

// Read in Node, before the runtime starts. The same files `wrangler d1
// migrations apply` runs, so a schema the tests pass against is the schema that
// ships — there is no second definition to drift.
const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));

/**
 * A stand-in for Google's signing key.
 *
 * Better Auth verifies an ID token properly — RS256, against the JWKS at
 * `googleapis.com/oauth2/v3/certs`, with the audience checked against the
 * configured client id. None of that is stubbed. A keypair is generated here,
 * its public half is served where Google's would be, and the tests sign real
 * tokens with the private half.
 *
 * Generated in Node rather than in a test because the outbound interceptor is
 * part of the runtime's configuration and has to exist before the first
 * request.
 */
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
        // Each test file gets its own storage, so one suite cannot leave a
        // group, a session or a rate behind for the next one to find.
        isolatedStorage: true,

        /**
         * Every outbound request the Worker makes, intercepted.
         *
         * Anything not explicitly answered fails loudly rather than reaching
         * the network: a test suite that quietly depends on Google being up
         * is not a test suite.
         */
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

          // Secrets the Worker expects. Real-shaped rather than empty, so
          // tests exercise the same code paths production does — an empty
          // RESEND_API_KEY, for instance, silently swaps the email sender
          // for one that logs.
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
