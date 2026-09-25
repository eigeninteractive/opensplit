import type { DrizzleD1Database } from "drizzle-orm/d1";
import { drizzle } from "drizzle-orm/d1";
import { createMiddleware } from "hono/factory";

import { type Auth, createAuth } from "./auth";
import { apiError } from "./schemas/common";

/**
 * What every handler can rely on being there.
 *
 * Hono carries per-request values in `c.var`, typed through this generic, so a
 * handler reads `c.var.db` rather than building its own. Before this, four
 * different helpers each called `drizzle(env.DB)` on every request and each
 * route resolved the session by hand — which works, and which would have been
 * repeated fifteen more times as the ledger routes land.
 */
export interface AppEnv {
  Bindings: Env;
  Variables: {
    db: DrizzleD1Database;
    auth: Auth;
    /** Null when nobody is signed in. Resolved once per request, at most. */
    session: Session | null;
  };
}

export interface Session {
  userId: string;
  isAnonymous: boolean;
}

/**
 * The same environment, for handlers that run behind `requireSession`.
 *
 * `session` is non-null here, which is the whole difference. Without it every
 * ledger handler would open with a `!` or a redundant null check on something
 * the middleware has already refused the request over — and a `!` is a claim
 * the compiler cannot check, repeated twenty times.
 */
export interface AuthedEnv {
  Bindings: Env;
  Variables: {
    db: DrizzleD1Database;
    auth: Auth;
    session: Session;
  };
}

/**
 * The database and the auth instance, on every request.
 *
 * Both are cheap to construct and neither touches the network here, so this is
 * applied globally rather than per route.
 */
export const services = createMiddleware<AppEnv>(async (c, next) => {
  c.set("db", drizzle(c.env.DB));
  c.set("auth", createAuth(c.env));
  await next();
});

/**
 * Resolves the session, and does not mind if there is not one.
 *
 * Applied to the identity routes, which have to behave differently depending on
 * whether somebody is already signed in — attaching an identity to the session
 * in hand versus authenticating as whoever owns it — and so need the answer
 * rather than a refusal.
 *
 * Costs one D1 read, which is why it is not global: the asset fallback and the
 * health check have no use for it.
 */
export const withSession = createMiddleware<AppEnv>(async (c, next) => {
  const resolved = await c.var.auth.api.getSession({ headers: c.req.raw.headers });
  c.set("session", resolved ? { userId: resolved.user.id, isAnonymous: Boolean(resolved.user.isAnonymous) } : null);
  await next();
});

/**
 * Refuses anything without a session, so the handler behind it can stop asking.
 *
 * The ledger routes use this. It is a first pass and nothing more: a group's
 * Durable Object re-checks membership itself and is the authority.
 */
export const requireSession = createMiddleware<AuthedEnv>(async (c, next) => {
  const resolved = await c.var.auth.api.getSession({ headers: c.req.raw.headers });
  if (!resolved) {
    return c.json(apiError("no_session", "Sign in first."), 401);
  }

  c.set("session", {
    userId: resolved.user.id,
    isAnonymous: Boolean(resolved.user.isAnonymous),
  });
  await next();
});
