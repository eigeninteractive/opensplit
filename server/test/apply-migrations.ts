import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

import { PRIYA, RAVI, ZARA } from "./group";

/** Every test file starts against a migrated, empty database. */
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

/**
 * The fixture people are accounts, as every real caller is: D1 refuses a
 * membership for an account that does not exist, and the group then forgets it.
 */
await env.DB.batch([RAVI, PRIYA, ZARA].map((id) => env.DB.prepare("insert or ignore into user (id, name, email, updated_at) values (?, ?, ?, ?)").bind(id, "", `${id}@fixture.invalid`, Date.now())));
