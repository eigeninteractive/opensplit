import { z } from "@hono/zod-openapi";

import { IdSchema } from "./common";

/** A signed-in identity, as the app sees it. */
export const AccountSchema = z
  .object({
    id: IdSchema,
    /** A guest: one device, no recovery. */
    isAnonymous: z.boolean(),
    /** Null for a guest. */
    email: z.email().nullable(),
    displayName: z.string().nullable(),
  })
  .openapi("Account");

/** The session in hand, or none. `token` is the bearer token on Android and null on the web (HttpOnly cookie). */
export const SessionSchema = z
  .object({
    account: AccountSchema.nullable(),
    token: z.string().nullable(),
  })
  .openapi("Session");

/**
 * What attaching an identity did. Flat rather than a union because the Dart
 * generator cannot read `oneOf`; `strandedUserId` is set exactly when
 * `outcome` is `replaced`.
 */
export const IdentityOutcomeSchema = z
  .object({
    outcome: z.enum(["kept", "replaced"]).openapi("IdentityOutcomeKind", {
      description: "kept: the account id did not change. replaced: a different account holds the session now, and `strandedUserId` names the one this device's ledger belongs to.",
    }),
    account: AccountSchema,
    token: z.string().nullable(),
    strandedUserId: IdSchema.nullable(),
  })
  .openapi("IdentityOutcome");

export const GoogleIdentityRequestSchema = z
  .object({
    /** From the native sign-in SDK. */
    idToken: z.string().min(1),
    nonce: z.string().nullable(),
    /** Whether the caller has warned that signing in to another account leaves this ledger behind. */
    allowSignIn: z.boolean(),
  })
  .openapi("GoogleIdentityRequest");

/** The browser flow, for the web, where Google answers by redirect. */
export const GoogleRedirectRequestSchema = z
  .object({
    /** Where Google sends the browser back to; must be on this origin. */
    callbackUrl: z.url(),
    allowSignIn: z.boolean(),
  })
  .openapi("GoogleRedirectRequest");

export const GoogleRedirectSchema = z.object({ url: z.url() }).openapi("GoogleRedirect");

export const EmailFlowSchema = z.enum(["linkPending", "signInPending"]).openapi("EmailFlow", {
  description: "linkPending: verifying keeps the current account id. signInPending: the address already has an account, so verifying replaces the session.",
});

export const EmailStartRequestSchema = z.object({ email: z.email() }).openapi("EmailStartRequest");

export const EmailStartResponseSchema = z.object({ flow: EmailFlowSchema }).openapi("EmailStartResponse");

export const EmailVerifyRequestSchema = z
  .object({
    email: z.email(),
    code: z.string().min(4).max(12),
    /** The value `POST /identity/email` returned. */
    flow: EmailFlowSchema,
  })
  .openapi("EmailVerifyRequest");

export type Account = z.infer<typeof AccountSchema>;
export type Session = z.infer<typeof SessionSchema>;
export type IdentityOutcome = z.infer<typeof IdentityOutcomeSchema>;
