import { build } from "./auth";

/**
 * What `auth generate` reads to emit `auth-schema.ts`: the Worker's own builder
 * over a stub D1, since generation only inspects options and plugins.
 */
/** Enough of a D1 for the adapter to recognise one; introspection finds nothing. */
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
