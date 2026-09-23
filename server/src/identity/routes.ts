import { createRoute, OpenAPIHono } from "@hono/zod-openapi";
import { APIError } from "better-auth/api";
import { and, eq, ne, sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import type { Context } from "hono";

import { user } from "../auth-schema";
import { type AppEnv, withSession } from "../context";
import { apiError, errorResponse, jsonResponse } from "../schemas/common";
import { EmailStartRequestSchema, EmailStartResponseSchema, EmailVerifyRequestSchema, GoogleIdentityRequestSchema, IdentityOutcomeSchema } from "../schemas/identity";
import { type Account, type IdentityOutcome, outcomeFor, toAccount } from "./outcome";

/**
 * Attaching an identity to a session, and the one decision that must not be got
 * wrong.
 *
 * ## Why these are not just Better Auth's endpoints
 *
 * The distinction that runs through this file is between *linking* an identity
 * to the session you already have and *authenticating* as whoever owns that
 * identity. They look almost identical from the outside and have opposite
 * consequences: the first keeps the account id, so every group recorded on this
 * device still belongs to the account holding it; the second mints or resumes a
 * different account and leaves the guest holding everything the person has
 * created so far, at which point they are a stranger to their own data.
 *
 * Getting that ordering wrong is not hypothetical. It is the bug this app
 * already shipped once: somebody who already had an account tapped a friend's
 * invite, had the slot claimed by a throwaway guest account, the single-use
 * token spent, and no way in afterwards. The only repair was the group's owner
 * issuing a fresh link.
 *
 * So each entry point below tries the linking call first and only falls back to
 * signing in when the identity provably belongs to somebody already — and
 * reports which of the two happened, because the caller has to say so.
 *
 * ## Why it is here and not in Dart
 *
 * It used to be four hundred lines of Dart that no test could reach without a
 * live backend. In TypeScript, inside the Worker, every branch is reachable
 * from `vitest` — including the ones that only fire when an identity is already
 * claimed, which is exactly where the damage happens.
 */

const googleRoute = createRoute({
  method: "post",
  operationId: "linkGoogle",
  path: "/google",
  tags: ["identity"],
  summary: "Attach Google to this session, or sign in with it",
  description: "Tries to link first, so the account id survives and nothing on the device has to move. Falls back to signing in only when the Google account provably belongs to somebody already, and only when allowSignIn says the cost has already been explained to the person.",
  request: {
    body: {
      required: true,
      content: { "application/json": { schema: GoogleIdentityRequestSchema } },
    },
  },
  responses: {
    200: jsonResponse(IdentityOutcomeSchema, "Linked, or signed in"),
    409: errorResponse("That Google account already has an account of its own, and allowSignIn was not set."),
  },
});

const emailStartRoute = createRoute({
  method: "post",
  operationId: "startEmailSignIn",
  path: "/email",
  tags: ["identity"],
  summary: "Send a sign-in code, and say which flow it started",
  request: {
    body: {
      required: true,
      content: { "application/json": { schema: EmailStartRequestSchema } },
    },
  },
  responses: {
    200: jsonResponse(EmailStartResponseSchema, "A code is on its way"),
  },
});

const emailVerifyRoute = createRoute({
  method: "post",
  operationId: "verifyEmailCode",
  path: "/email/verify",
  tags: ["identity"],
  summary: "Complete the flow that POST /identity/email started",
  responses: {
    200: jsonResponse(IdentityOutcomeSchema, "Attached, or signed in"),
    401: errorResponse("That code was for a flow this session cannot finish."),
  },
  request: {
    body: {
      required: true,
      content: { "application/json": { schema: EmailVerifyRequestSchema } },
    },
  },
});

export function identityRoutes() {
  const routes = new OpenAPIHono<AppEnv>();

  // Every route here behaves differently with and without a session, so the
  // answer is resolved once, up front, rather than three times by hand.
  routes.use("*", withSession);

  routes.openapi(googleRoute, async (c) => {
    const { auth, session } = c.var;
    const { idToken, nonce, allowSignIn } = c.req.valid("json");
    const before = session?.userId ?? null;
    const credential = {
      provider: "google" as const,
      idToken: { token: idToken, nonce },
    };

    // Nobody is signed in, so there is nothing to attach this to and nothing
    // at stake. Straight to a sign-in, which for a new account is a sign-up.
    if (before === null) {
      const signedIn = await auth.api.signInSocial({
        body: credential,
        headers: c.req.raw.headers,
        returnHeaders: true,
      });
      return c.json(sessionBody(c, signedIn.headers, outcomeFor(toAccount(sessionFrom(signedIn.response)), null)), 200);
    }

    try {
      const linked = await auth.api.linkSocialAccount({
        body: credential,
        headers: c.req.raw.headers,
        returnHeaders: true,
      });

      // Attached to the session in hand, so the id did not move and nothing
      // on the device has to.
      await settle(c.var.db, before);
      return c.json(sessionBody(c, linked.headers, outcomeFor(await accountById(c.var.db, before), before)), 200);
    } catch (error) {
      if (!isAlreadyClaimed(error)) throw error;

      // That Google account already belongs to somebody. Signing in is the
      // opposite outcome from linking — it leaves this device's ledger behind
      // — so the caller has to stop and say what that costs before it
      // happens. By the time the session is replaced it is too late to ask.
      if (!allowSignIn) {
        return c.json(apiError("identity_already_in_use", "That Google account already has an OpenSplit account of its own."), 409);
      }
    }

    // Usually a different account — but not always. If it is the same address
    // as an email account already holding this session, Better Auth attaches
    // the identity to it and the id does not change at all. `outcomeFor` works
    // that out from the ids rather than assuming.
    const signedIn = await auth.api.signInSocial({
      body: credential,
      headers: c.req.raw.headers,
      returnHeaders: true,
    });
    return c.json(sessionBody(c, signedIn.headers, outcomeFor(toAccount(sessionFrom(signedIn.response)), before)), 200);
  });

  routes.openapi(emailStartRoute, async (c) => {
    const { auth, session } = c.var;
    const email = c.req.valid("json").email.trim().toLowerCase();
    const before = session?.userId ?? null;

    // Nobody is signed in: this is somebody arriving, so it is a sign-in, and
    // for an address with no account yet it is a sign-up. Creating the account
    // IS the request.
    //
    // The same branch covers an address that already belongs to somebody else
    // while a guest session is open. It deliberately still sends a sign-in
    // code — only the address's real owner can read it — and the flow it
    // reports is what tells the app to warn that continuing leaves this
    // device's ledger behind.
    if (before === null || (await emailBelongsToAnother(c.var.db, email, before))) {
      await auth.api.sendVerificationOTP({ body: { email, type: "sign-in" } });
      return c.json({ flow: "signInPending" as const }, 200);
    }

    // Attaching the address to the session in hand, which is what keeps the
    // account id — and therefore every group on this device — intact.
    await auth.api.requestEmailChangeEmailOTP({
      body: { newEmail: email },
      headers: c.req.raw.headers,
    });
    return c.json({ flow: "linkPending" as const }, 200);
  });

  routes.openapi(emailVerifyRoute, async (c) => {
    const { auth, session } = c.var;
    const { code, flow } = c.req.valid("json");
    const email = c.req.valid("json").email.trim().toLowerCase();
    const before = session?.userId ?? null;

    if (flow === "linkPending") {
      if (before === null) {
        return c.json(apiError("no_session", "That code was for attaching an address to a session, and there is no session to attach it to."), 401);
      }

      const changed = await auth.api.changeEmailEmailOTP({
        body: { newEmail: email, otp: code },
        headers: c.req.raw.headers,
        returnHeaders: true,
      });

      await settle(c.var.db, before);
      return c.json(sessionBody(c, changed.headers, outcomeFor(await accountById(c.var.db, before), before)), 200);
    }

    const signedIn = await auth.api.signInEmailOTP({
      body: { email, otp: code },
      headers: c.req.raw.headers,
      returnHeaders: true,
    });

    return c.json(sessionBody(c, signedIn.headers, outcomeFor(toAccount(signedIn.response.user), before)), 200);
  });

  return routes;
}

/**
 * The session out of a social sign-in.
 *
 * `signInSocial` answers in one of two shapes: a URL for a browser to visit, or
 * a finished session. With an ID token in hand it is always the second — the
 * redirect shape belongs to the web flow, which goes through Better Auth's own
 * endpoint rather than this one.
 *
 * Narrowed with a check rather than a cast, so that if that ever stops being
 * true it fails here, loudly, instead of quietly producing an outcome with no
 * account in it and a client that believes it is signed in.
 */
function sessionFrom<T extends object>(response: T): Extract<T, { user: unknown }>["user"] {
  if (!("user" in response)) {
    throw new Error("Google sign-in answered with a redirect, not a session");
  }
  return (response as { user: Extract<T, { user: unknown }>["user"] }).user;
}

/**
 * Better Auth's refusal when the identity is already somebody's.
 *
 * Matched on codes rather than on message text, and narrowly: any other
 * failure is rethrown. A fallback that fired on, say, a network blip would sign
 * somebody out of their own data for no reason.
 *
 * The codes are string literals because Better Auth only exports them from a
 * transitive internal package, which is a worse thing to depend on than a test.
 * `refuses when the Google account is already somebody else's` is that test,
 * and it is what caught this list being wrong the first time: a code missing
 * from it does not fail open, it turns the refusal into a 500 and the app never
 * gets to ask the question that protects the ledger.
 */
const ALREADY_CLAIMED = new Set(["SOCIAL_ACCOUNT_ALREADY_LINKED", "ACCOUNT_ALREADY_LINKED", "ACCOUNT_NOT_LINKED", "USER_ALREADY_EXISTS"]);

function isAlreadyClaimed(error: unknown): boolean {
  if (!(error instanceof APIError)) return false;
  return ALREADY_CLAIMED.has((error as { body?: { code?: string } }).body?.code ?? "");
}

/**
 * Whether the address already belongs to somebody else.
 *
 * Asked directly rather than inferred from a failure. The alternative is to
 * attempt the change and read the error, and a misread error here silently
 * mints a new empty account and strands every group on this device.
 */
async function emailBelongsToAnother(db: DrizzleD1Database, email: string, selfId: string): Promise<boolean> {
  const rows = await db
    .select({ id: user.id })
    .from(user)
    .where(and(eq(sql`lower(${user.email})`, email), ne(user.id, selfId)))
    .limit(1);

  return rows.length > 0;
}

/**
 * The account is no longer a guest.
 *
 * Written straight to the column rather than through `updateUser`, because
 * `isAnonymous` is a plugin field and not something the user-update endpoint
 * accepts. Nothing caches it — sessions are resolved from the database on each
 * request — so a direct write is immediately true everywhere.
 */
async function settle(db: DrizzleD1Database, userId: string): Promise<void> {
  await db.update(user).set({ isAnonymous: false }).where(eq(user.id, userId));
}

async function accountById(db: DrizzleD1Database, id: string): Promise<Account> {
  const [row] = await db
    .select({
      id: user.id,
      email: user.email,
      name: user.name,
      isAnonymous: user.isAnonymous,
    })
    .from(user)
    .where(eq(user.id, id))
    .limit(1);

  if (!row) throw new Error(`No user ${id} after linking`);
  return toAccount(row);
}

/**
 * Hands the session back in both shapes at once.
 *
 * Better Auth's `Set-Cookie` is forwarded untouched, which is what the web
 * build runs on — an `HttpOnly` cookie the page's own JavaScript cannot read,
 * so a compromised dependency cannot steal the session. `set-auth-token`
 * carries the same session as a bearer token, which is what Android stores,
 * because a background isolate woken by a push has no cookie jar to read from.
 */
function sessionBody(c: Context<AppEnv>, headers: Headers, outcome: IdentityOutcome) {
  for (const cookie of headers.getSetCookie()) {
    c.header("Set-Cookie", cookie, { append: true });
  }
  return { ...outcome, token: headers.get("set-auth-token") };
}
