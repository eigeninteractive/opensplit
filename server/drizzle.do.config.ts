import { defineConfig } from "drizzle-kit";

/**
 * One group's ledger, inside its Durable Object.
 *
 * A separate schema and a separate migration folder from D1's, because they
 * are different databases with nothing in common — and because these
 * migrations are bundled into the Worker as text and applied by the object to
 * itself, lazily, on its first open after a deploy.
 */
export default defineConfig({
  dialect: "sqlite",
  driver: "durable-sqlite",
  schema: "./src/db/group/schema.ts",
  out: "./src/do/migrations",
});
