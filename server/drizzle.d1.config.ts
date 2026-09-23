import { defineConfig } from "drizzle-kit";

/**
 * The D1 schema: Better Auth's generated tables plus our four.
 *
 * Generated here, applied by `wrangler d1 migrations apply`. drizzle-kit's own
 * `migrate` would need the `d1-http` driver, an API token and an account id;
 * generating locally and applying with the tool that already holds the binding
 * keeps the whole loop offline.
 */
export default defineConfig({
  dialect: "sqlite",
  schema: ["./src/db/d1/schema.ts", "./src/auth-schema.ts"],
  out: "./migrations",
});
