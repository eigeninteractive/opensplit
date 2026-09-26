import { type DrizzleD1Database, drizzle } from "drizzle-orm/d1";
import { createMiddleware } from "hono/factory";

import { type Auth, createAuth } from "./auth";
import { apiError } from "./schemas/common";

export interface Session {
  userId: string;
  isAnonymous: boolean;
}

interface Services {
  db: DrizzleD1Database;
  auth: Auth;
}

export interface AppEnv {
  Bindings: Env;
  Variables: Services & { session: Session | null };
}

/** The environment behind `requireSession`, where the session is never null. */
export interface AuthedEnv {
  Bindings: Env;
  Variables: Services & { session: Session };
}

export const services = createMiddleware<AppEnv>(async (c, next) => {
  c.set("db", drizzle(c.env.DB));
  c.set("auth", createAuth(c.env));
  await next();
});

async function resolveSession(auth: Auth, headers: Headers): Promise<Session | null> {
  const resolved = await auth.api.getSession({ headers });
  return resolved ? { userId: resolved.user.id, isAnonymous: Boolean(resolved.user.isAnonymous) } : null;
}

/** For routes that behave differently with and without a session. */
export const withSession = createMiddleware<AppEnv>(async (c, next) => {
  c.set("session", await resolveSession(c.var.auth, c.req.raw.headers));
  await next();
});

/** A first pass only: the group object re-checks membership and is the authority. */
export const requireSession = createMiddleware<AuthedEnv>(async (c, next) => {
  const session = await resolveSession(c.var.auth, c.req.raw.headers);
  if (!session) return c.json(apiError("no_session", "Sign in first."), 401);
  c.set("session", session);
  await next();
});
