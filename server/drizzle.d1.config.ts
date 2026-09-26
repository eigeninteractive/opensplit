import { defineConfig } from "drizzle-kit";

/** D1: our tables plus Better Auth's. Applied with `wrangler d1 migrations apply`. */
export default defineConfig({
  dialect: "sqlite",
  schema: ["./src/db/d1/schema.ts", "./src/auth-schema.ts"],
  out: "./migrations",
});
