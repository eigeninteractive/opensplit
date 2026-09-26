import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

/** Every test file starts against a migrated, empty database. */
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
