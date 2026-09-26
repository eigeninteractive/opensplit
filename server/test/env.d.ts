import type { D1Migration } from "@cloudflare/vitest-plugin";

/** Bindings that exist only under test, declared where the runtime expects them. */
declare global {
  namespace Cloudflare {
    interface Env {
      /** Supplied by vitest.config.ts, read from migrations/ in Node. */
      TEST_MIGRATIONS: D1Migration[];
      /** The private half of the stand-in Google signing key. See test/google.ts. */
      TEST_GOOGLE_PRIVATE_JWK: unknown;
    }
  }
}
