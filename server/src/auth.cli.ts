import { build } from "./auth";

/**
 * The instance `@better-auth/cli generate` reads to work out the schema.
 *
 * It exists because the real one is a function of a live `Env` — there is no
 * D1 binding in Node, and there should not be. Schema generation only inspects
 * the options and the plugin list, so a stub that satisfies the type is enough,
 * and nothing here ever executes a query.
 *
 * The important property is that this calls the *same* builder the Worker does.
 * A second copy of the options would drift, and the first sign that it had
 * would be a missing column in production.
 */
/**
 * Enough of a D1 to be recognised as one.
 *
 * The Kysely adapter identifies D1 by the presence of `batch`, `exec` and
 * `prepare`, and then builds an index introspector that reads the existing
 * schema. Against an empty result set that introspection simply finds nothing,
 * which is exactly right: this generates the schema from scratch.
 */
const emptyStatement = {
  bind: () => emptyStatement,
  first: async () => null,
  run: async () => ({ results: [], success: true, meta: {} }),
  all: async () => ({ results: [], success: true, meta: {} }),
  raw: async () => [],
};

const emptyD1 = {
  prepare: () => emptyStatement,
  batch: async () => [],
  exec: async () => ({ count: 0, duration: 0 }),
  dump: async () => new ArrayBuffer(0),
  withSession: () => emptyD1,
} as unknown as D1Database;

const generateOnly = {
  DB: emptyD1,
  APP_ORIGIN: "https://opensplit.eigeninteractive.com",
  BETTER_AUTH_SECRET: "generate-only",
  GOOGLE_CLIENT_ID: "generate-only",
  GOOGLE_CLIENT_SECRET: "generate-only",
  RESEND_API_KEY: "",
  FCM_PROJECT_ID: "",
  FCM_SERVICE_ACCOUNT: "",
} as unknown as Env;

export const auth = build(generateOnly);
