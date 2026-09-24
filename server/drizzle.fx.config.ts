import { defineConfig } from "drizzle-kit";

/**
 * The rate object's own database.
 *
 * A third schema and a third migration folder, for the same reason the group's
 * is separate from D1's: they are different databases with nothing in common.
 * This one is bundled into the Worker as text and applied by the object to
 * itself, lazily, on its first open after a deploy.
 */
export default defineConfig({
  dialect: "sqlite",
  driver: "durable-sqlite",
  schema: "./src/db/fx/schema.ts",
  out: "./src/do/fx/migrations",
});
