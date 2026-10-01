import { defineConfig } from "drizzle-kit";

/** One group's database. Bundled into the Worker; each object migrates itself on first open. */
export default defineConfig({
  dialect: "sqlite",
  driver: "durable-sqlite",
  schema: "./src/db/group/schema.ts",
  out: "./src/do/group/migrations",
});
