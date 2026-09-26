import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { APIError } from "better-auth/api";
import { and, eq, ne, sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import type { Context } from "hono";

import { maybeSignedIn } from "../api/routing";
import { user } from "../auth-schema";
import type { AppEnv } from "../context";
import { apiError, errorResponse, jsonBody, jsonResponse } from "../schemas/common";
import { EmailStartRequestSchema, EmailStartResponseSchema, EmailVerifyRequestSchema, GoogleIdentityRequestSchema, GoogleRedirectRequestSchema, GoogleRedirectSchema, IdentityOutcomeSchema, SessionSchema } from "../schemas/identity";
import { outcomeFor, toAccount } from "./outcome";

/**
 * Every session operation the app performs, as contract types over Better
 * Auth's server API. Its own HTTP handler is mounted only for the OAuth
 * callback Google redirects to.
 *
 * Attaching an identity to the session in hand and signing in to another
 * account are opposite outcomes (the first keeps this device's ledger), so the
 * server decides which happened and says so, and refuses a sign-in that would
 * strand a ledger until the caller says it has warned the person.
 */

const guestRoute = createRoute({
  ...maybeSignedIn,
  method: "post",
  operationId: "signInAsGuest",
  path: "/identity/guest",
  tags: ["identity"],
  summary: "Start a guest account on this device",
  responses: { 200: jsonResponse(IdentityOutcomeSchema, "Signed in as a new guest") },
});

const sessionRoute = createRoute({
  security: maybeSignedIn.security,
  method: "get",
  operationId: "getSession",
  path: "/identity/session",
  tags: ["identity"],
  summary: "The session in hand, or none",
  responses: { 200: jsonResponse(SessionSchema, "The account, and a rotated bearer token if one was issued") },
});

const signOutRoute = createRoute({
  security: maybeSignedIn.security,
  method: "post",
  operationId: "signOut",
  path: "/identity/sign-out",
  tags: ["identity"],
  summary: "End this session",
  responses: { 204: { description: "Signed out" } },
});

const googleRoute = createRoute({
  ...maybeSignedIn,
  method: "post",
  operationId: "linkGoogle",
  path: "/identity/google",
  tags: ["identity"],
  summary: "Attach Google to this session, or sign in with it",
  description: "Links first, so the account id survives. Signs in instead only when the Google account already belongs to somebody, and only with allowSignIn.",
  request: { body: jsonBody(GoogleIdentityRequestSchema) },
  responses: {
    200: jsonResponse(IdentityOutcomeSchema, "Linked, or signed in"),
    409: errorResponse("That Google account already has an account of its own, and allowSignIn was not set."),
  },
});

const googleRedirectRoute = createRoute({
  ...maybeSignedIn,
  method: "post",
  operationId: "startGoogleRedirect",
  path: "/identity/google/redirect",
  tags: ["identity"],
  summary: "Where to send the browser to link or sign in with Google",
  description: "Links to the session in hand unless allowSignIn is set or there is none. Afterwards, read `GET /identity/session`.",
  request: { body: jsonBody(GoogleRedirectRequestSchema) },
  responses: { 200: jsonResponse(GoogleRedirectSchema, "The URL to visit") },
});

const emailStartRoute = createRoute({
  ...maybeSignedIn,
  method: "post",
  operationId: "startEmailSignIn",
  path: "/identity/email",
  tags: ["identity"],
  summary: "Send a sign-in code, and say which flow it started",
  request: { body: jsonBody(EmailStartRequestSchema) },
  responses: { 200: jsonResponse(EmailStartResponseSchema, "A code is on its way") },
});

const emailVerifyRoute = createRoute({
  ...maybeSignedIn,
  method: "post",
  operationId: "verifyEmailCode",
  path: "/identity/email/verify",
  tags: ["identity"],
  summary: "Complete the flow that POST /identity/email started",
  request: { body: jsonBody(EmailVerifyRequestSchema) },
  responses: {
    200: jsonResponse(IdentityOutcomeSchema, "Attached, or signed in"),
    400: errorResponse("The code is wrong or has expired."),
    401: errorResponse("That code was for a flow this session cannot finish."),
  },
});

const google = (idToken: string, nonce: string | null) => ({ provider: "google" as const, idToken: { token: idToken, nonce: nonce ?? undefined } });

export function identityRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(guestRoute, async (c) => {
    const signedIn = await c.var.auth.api.signInAnonymous({ headers: c.req.raw.headers, returnHeaders: true });
    if (!signedIn.response) throw new Error("Anonymous sign-in returned no session");
    return c.json(outcomeFor(toAccount(signedIn.response.user), c.var.session?.userId ?? null, forward(c, signedIn.headers)), 200);
  });

  routes.openapi(sessionRoute, async (c) => {
    const current = await c.var.auth.api.getSession({ headers: c.req.raw.headers, returnHeaders: true });
    const token = forward(c, current.headers);
    return c.json({ account: current.response ? toAccount(current.response.user) : null, token }, 200);
  });

  routes.openapi(signOutRoute, async (c) => {
    // The device signs out either way; a session row nobody holds expires on its own.
    try {
      const done = await c.var.auth.api.signOut({ headers: c.req.raw.headers, returnHeaders: true });
      forward(c, done.headers);
    } catch (error) {
      if (!(error instanceof APIError)) throw error;
    }
    return c.body(null, 204);
  });

  routes.openapi(googleRoute, async (c) => {
    const { auth, session } = c.var;
    const { idToken, nonce, allowSignIn } = c.req.valid("json");
    const before = session?.userId ?? null;

    if (before !== null) {
      try {
        const linked = await auth.api.linkSocialAccount({ body: google(idToken, nonce), headers: c.req.raw.headers, returnHeaders: true });
        await settle(c.var.db, before);
        return c.json(outcomeFor(await accountById(c.var.db, before), before, forward(c, linked.headers)), 200);
      } catch (error) {
        if (!isAlreadyClaimed(error)) throw error;
        if (!allowSignIn) return c.json(apiError("identity_already_in_use", "That Google account already has an OpenSplit account of its own."), 409);
      }
    }

    // A new account is a sign-up. The same address as the session's email account lands on that same account, which `outcomeFor` sees.
    const signedIn = await auth.api.signInSocial({ body: google(idToken, nonce), headers: c.req.raw.headers, returnHeaders: true });
    if (!("user" in signedIn.response)) throw new Error("Google sign-in answered with a redirect, not a session");
    return c.json(outcomeFor(toAccount(signedIn.response.user), before, forward(c, signedIn.headers)), 200);
  });

  routes.openapi(googleRedirectRoute, async (c) => {
    const { callbackUrl, allowSignIn } = c.req.valid("json");
    const body = { provider: "google" as const, callbackURL: callbackUrl, errorCallbackURL: callbackUrl, disableRedirect: true };
    const link = c.var.session !== null && !allowSignIn;
    const started = link ? await c.var.auth.api.linkSocialAccount({ body, headers: c.req.raw.headers, returnHeaders: true }) : await c.var.auth.api.signInSocial({ body, headers: c.req.raw.headers, returnHeaders: true });

    // The OAuth state cookie has to reach the browser for the callback to verify.
    forward(c, started.headers);
    if (!("url" in started.response) || !started.response.url) throw new Error("Google sign-in did not answer with a URL to visit");
    return c.json({ url: started.response.url }, 200);
  });

  routes.openapi(emailStartRoute, async (c) => {
    const { auth, session } = c.var;
    const email = c.req.valid("json").email.trim().toLowerCase();

    // Nobody signed in, or the address is somebody else's: a sign-in code, which only the owner can read.
    if (session === null || (await emailBelongsToAnother(c.var.db, email, session.userId))) {
      await auth.api.sendVerificationOTP({ body: { email, type: "sign-in" } });
      return c.json({ flow: "signInPending" as const }, 200);
    }

    await auth.api.requestEmailChangeEmailOTP({ body: { newEmail: email }, headers: c.req.raw.headers });
    return c.json({ flow: "linkPending" as const }, 200);
  });

  routes.openapi(emailVerifyRoute, async (c) => {
    const { auth, session } = c.var;
    const { code, flow } = c.req.valid("json");
    const email = c.req.valid("json").email.trim().toLowerCase();
    const before = session?.userId ?? null;

    if (flow === "linkPending") {
      if (before === null) return c.json(apiError("no_session", "That code was for attaching an address to a session, and there is no session to attach it to."), 401);
      const changed = await auth.api.changeEmailEmailOTP({ body: { newEmail: email, otp: code }, headers: c.req.raw.headers, returnHeaders: true });
      await settle(c.var.db, before);
      return c.json(outcomeFor(await accountById(c.var.db, before), before, forward(c, changed.headers)), 200);
    }

    const signedIn = await auth.api.signInEmailOTP({ body: { email, otp: code }, headers: c.req.raw.headers, returnHeaders: true });
    return c.json(outcomeFor(toAccount(signedIn.response.user), before, forward(c, signedIn.headers)), 200);
  });
}

/** Passes Better Auth's cookies through, and returns the bearer token it issued (null on the web). */
function forward(c: Context<AppEnv>, headers: Headers): string | null {
  for (const cookie of headers.getSetCookie()) c.header("Set-Cookie", cookie, { append: true });
  return headers.get("set-auth-token");
}

const ALREADY_CLAIMED = new Set(["SOCIAL_ACCOUNT_ALREADY_LINKED", "ACCOUNT_ALREADY_LINKED", "ACCOUNT_NOT_LINKED", "USER_ALREADY_EXISTS"]);

function isAlreadyClaimed(error: unknown): boolean {
  return error instanceof APIError && ALREADY_CLAIMED.has(error.body?.code ?? "");
}

async function emailBelongsToAnother(db: DrizzleD1Database, email: string, selfId: string): Promise<boolean> {
  const row = await db
    .select({ id: user.id })
    .from(user)
    .where(and(eq(sql`lower(${user.email})`, email), ne(user.id, selfId)))
    .get();
  return row !== undefined;
}

/** An account with an identity attached is no longer a guest. */
async function settle(db: DrizzleD1Database, userId: string): Promise<void> {
  await db.update(user).set({ isAnonymous: false }).where(eq(user.id, userId));
}

async function accountById(db: DrizzleD1Database, id: string) {
  const row = await db.select().from(user).where(eq(user.id, id)).get();
  if (!row) throw new Error(`No user ${id} after linking`);
  return toAccount(row);
}
