import { defineConfig } from "drizzle-kit";

/** The rate object's database, migrated the same way as a group's. */
export default defineConfig({
  dialect: "sqlite",
  driver: "durable-sqlite",
  schema: "./src/db/fx/schema.ts",
  out: "./src/do/fx/migrations",
});
