import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

/**
 * Every test file starts against a migrated, empty database.
 *
 * `isolatedStorage` gives each file its own D1, so this runs per file and the
 * rows one suite writes are invisible to the next.
 */
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
