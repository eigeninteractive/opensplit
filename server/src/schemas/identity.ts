import { z } from "@hono/zod-openapi";

import { IdSchema } from "./common";

/**
 * A signed-in identity, as the app sees it.
 *
 * Generated into Dart as `Account`.
 */
export const AccountSchema = z
  .object({
    id: IdSchema,

    /**
     * True for an account created by signing in as a guest.
     *
     * Guest means one device and no recovery: on the web, clearing site data
     * destroys the account permanently. It also gates destructive actions.
     */
    isAnonymous: z.boolean(),

    /** Null for a guest. The plugin's placeholder address is never reported. */
    email: z.email().nullable(),
    displayName: z.string().nullable(),
  })
  .openapi("Account");

/**
 * What attaching an identity did.
 *
 * "Did this device's ledger stay with the account" is the only question a
 * caller has, and answering it by diffing ids put that derivation at every call
 * site. Which case applies cannot be inferred from which code path ran either:
 * signing in with Google using the address an existing email account already
 * owns lands on *that same account*, so the sign-in branch ran and yet nothing
 * moved. Only the resulting id settles it, so the server settles it.
 *
 * ## Why this is flat, and not `z.discriminatedUnion`
 *
 * It was a union, which emits `oneOf` — and `oneOf` is where the Dart generator
 * gives up, in the same way it does for `EventPayload`. It flattens the two
 * branches into one class carrying every field from both, **all required**, so
 * `IdentityOutcome.fromJson` asserted that a `kept` outcome had a
 * `strandedUserId` and threw when it did not. That is not a weaker client: it
 * is a client that cannot read the most common answer this endpoint gives.
 *
 * So `strandedUserId` is nullable and `outcome` says when to read it. The
 * pairing is still enforced where it matters — `outcomeFor` is the only thing
 * that constructs one of these, and its return type is the union — which is the
 * same argument `append()` makes for event payloads.
 */
export const IdentityOutcomeSchema = z
  .object({
    outcome: z.enum(["kept", "replaced"]).openapi({
      description: "kept: the account id did not change, so nothing on the device has to move. replaced: a different account holds the session now, and `strandedUserId` names the one this device's ledger stays with.",
    }),
    account: AccountSchema,

    /** Null on web, where the session is an HttpOnly cookie instead. */
    token: z.string().nullable(),

    /**
     * The account this device's local database still belongs to, when the
     * session was replaced. Null when it was kept — which database was left
     * behind is the only part of the transition a caller can act on, and there
     * is nothing to act on when nothing moved.
     */
    strandedUserId: IdSchema.nullable(),
  })
  .openapi("IdentityOutcome");

export const GoogleIdentityRequestSchema = z
  .object({
    /** A Google ID token, minted in-process by the native sign-in SDK. */
    idToken: z.string().min(1),
    /** The nonce the native sign-in was started with, if the platform used one. */
    nonce: z.string().nullable(),

    /**
     * Whether the caller has already been told what signing in would cost.
     *
     * When false and the Google account belongs to somebody else, the
     * request is refused so the app can say that continuing leaves this
     * device's ledger behind. By the time the session is replaced it is too
     * late to ask.
     */
    allowSignIn: z.boolean(),
  })
  .openapi("GoogleIdentityRequest");

/**
 * What asking for an email code actually started.
 *
 * Attaching an address to the session you already have and signing in to an
 * account that already exists are different operations issuing different
 * tokens, and verifying a code against the wrong one fails with a message about
 * an expired token that has nothing to do with what went wrong. So the answer
 * travels back with the code rather than being guessed at afterwards.
 */
export const EmailFlowSchema = z.enum(["linkPending", "signInPending"]).openapi("EmailFlow", {
  description: "linkPending: verifying keeps the current account id, so every group on this device still belongs to it. signInPending: the address already had an account, so verifying REPLACES the session, and anything recorded as a guest stays with the guest account.",
});

export const EmailStartRequestSchema = z.object({ email: z.email() }).openapi("EmailStartRequest");

export const EmailStartResponseSchema = z.object({ flow: EmailFlowSchema }).openapi("EmailStartResponse");

export const EmailVerifyRequestSchema = z
  .object({
    email: z.email(),
    /** Eight digits. A code, not a magic link — see the sender. */
    code: z.string().min(4).max(12),
    /** Must be the value `POST /identity/email` returned. */
    flow: EmailFlowSchema,
  })
  .openapi("EmailVerifyRequest");
