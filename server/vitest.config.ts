import path from "node:path";

import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { exportJWK, generateKeyPair } from "jose";
import { defineConfig } from "vitest/config";

/**
 * Tests run inside workerd, against real Durable Objects, a real D1 and a real
 * KV — the same Miniflare `wrangler dev` uses — rather than against mocks.
 *
 * That matters here more than usual: most of what this server does is
 * enforce rules at a write, and a test double for the thing doing the
 * enforcing proves only that the double agrees with itself.
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
         * A front end the server suite owns, in place of `../build/web`.
         *
         * Three files, standing in for the landing page, the client shell and
         * the 404 page — which is exactly the three branches of the catch-all
         * in `app.ts`. Pointing this at the real bundle instead would make the
         * server's own tests depend on a Flutter build having been run, and
         * would have them assert on the contents of a generated document that
         * nothing here controls.
         *
         * Only the directory is overridden. `binding` and `run_worker_first`
         * are the deployed values, restated here because this block replaces
         * the one in wrangler.jsonc rather than merging with it — and a suite
         * that quietly ran with a different routing model than production is
         * worse than no suite.
         */
        assets: {
          directory: path.join(import.meta.dirname, "test/fixtures/assets"),
          binding: "ASSETS",
          run_worker_first: ["/api/*"],
        },

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

          // The deployed origin lives in wrangler.jsonc, because that is the
          // value whose being wrong breaks sign-in for everybody. Stated again
          // here so the suite does not inherit it, and does not depend on an
          // untracked .dev.vars either: this file is the whole environment the
          // tests run in.
          APP_ORIGIN: "http://localhost:8787",

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
