import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { googleIdToken } from "./google";
import { signInAsGuest } from "./session";

/**
 * The branches that decide whether somebody's ledger survives.
 *
 * This is the suite that justifies moving link-or-sign-in out of Dart. Every
 * case below was unreachable from a Flutter test without a live backend, and
 * the one that matters most — an identity that already belongs to somebody —
 * is the one nobody would think to set up by hand.
 */

interface Outcome {
  outcome: "kept" | "replaced";
  account: { id: string; isAnonymous: boolean; email: string | null };
  token: string | null;

  /**
   * Present and null on a `kept` outcome, rather than absent.
   *
   * Not a style choice. A discriminated union here emits `oneOf`, which the
   * Dart generator flattens into one class with every field from both branches
   * required — so an absent `strandedUserId` made the most common answer this
   * endpoint gives fail to decode on the device. `everyOutcomeCarriesTheField`
   * below is what holds it present.
   */
  strandedUserId: string | null;
}

/**
 * Every field the generated client declares required, actually there.
 *
 * Asserted on the parsed body rather than trusted from the type, because the
 * type is this file's own description of the wire and the wire is what the
 * device has to read.
 */
function everyOutcomeCarriesTheField(body: Outcome) {
  expect(Object.keys(body).sort()).toEqual(["account", "outcome", "strandedUserId", "token"]);
}

async function continueWithGoogle(idToken: string, options: { token?: string; allowSignIn?: boolean } = {}): Promise<Response> {
  return workerExports.default.fetch("https://opensplit.test/api/identity/google", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    body: JSON.stringify({
      idToken,
      nonce: null,
      allowSignIn: options.allowSignIn ?? false,
    }),
  });
}

describe("continuing with Google", () => {
  it("signs in when there is no session to attach to", async () => {
    const token = await googleIdToken({
      sub: "google-new",
      email: "new@example.com",
    });

    const response = await continueWithGoogle(token);
    expect(response.status).toBe(200);

    const body = (await response.json()) as Outcome;
    // Nothing was at stake, so nothing was left behind.
    expect(body.outcome).toBe("kept");
    everyOutcomeCarriesTheField(body);
    expect(body.strandedUserId).toBeNull();
    expect(body.account.email).toBe("new@example.com");
    expect(body.account.isAnonymous).toBe(false);
  });

  /**
   * The case the whole design turns on.
   *
   * A guest has been recording expenses. Attaching Google must keep the same
   * account id, because every member row in every group points at it. A new id
   * here would leave them a stranger to their own data.
   */
  it("links to a guest session, keeping the account id", async () => {
    const guest = await signInAsGuest();
    const token = await googleIdToken({
      sub: "google-linker",
      email: "linker@example.com",
    });

    const response = await continueWithGoogle(token, { token: guest.token });
    expect(response.status).toBe(200);

    const body = (await response.json()) as Outcome;
    expect(body.outcome).toBe("kept");
    expect(body.account.id).toBe(guest.id);
  });

  it("stops being a guest once an identity is attached", async () => {
    const guest = await signInAsGuest();
    const token = await googleIdToken({
      sub: "google-settles",
      email: "settles@example.com",
    });

    await continueWithGoogle(token, { token: guest.token });

    const row = await env.DB.prepare("select is_anonymous as anon from user where id = ?1").bind(guest.id).first<{ anon: number }>();

    // Still a guest here would mean destructive actions stay gated and the
    // account reads as throwaway despite having a real identity on it.
    expect(row?.anon).toBeFalsy();
  });

  /**
   * The refusal that has to happen before anything moves.
   *
   * Signing in would abandon this device's ledger, so the server refuses and
   * makes the app say so. By the time the session is replaced it is too late
   * to ask.
   */
  it("refuses when the Google account is already somebody else's", async () => {
    const owner = await googleIdToken({
      sub: "google-taken",
      email: "taken@example.com",
    });
    await continueWithGoogle(owner);

    const guest = await signInAsGuest();
    const response = await continueWithGoogle(await googleIdToken({ sub: "google-taken", email: "taken@example.com" }), { token: guest.token });

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({
      error: { code: "identity_already_in_use" },
    });
  });

  it("signs in and names the stranded account once told the cost is accepted", async () => {
    const first = await continueWithGoogle(await googleIdToken({ sub: "google-owner", email: "owner@example.com" }));
    const owner = (await first.json()) as Outcome;

    const guest = await signInAsGuest();
    const response = await continueWithGoogle(await googleIdToken({ sub: "google-owner", email: "owner@example.com" }), { token: guest.token, allowSignIn: true });

    expect(response.status).toBe(200);
    const body = (await response.json()) as Outcome;

    // The session moved to the account that owns the identity, and the caller
    // is told which local database was left behind — the only part of the
    // transition it can act on.
    expect(body.outcome).toBe("replaced");
    everyOutcomeCarriesTheField(body);
    expect(body.account.id).toBe(owner.account.id);
    expect(body.strandedUserId).toBe(guest.id);
  });

  it("hands back a bearer token for Android to store", async () => {
    const response = await continueWithGoogle(await googleIdToken({ sub: "google-token", email: "token@example.com" }));

    const body = (await response.json()) as Outcome;
    expect(body.token).toBeTruthy();
  });

  it("sets an HttpOnly cookie for the web build", async () => {
    const response = await continueWithGoogle(
      await googleIdToken({
        sub: "google-cookie",
        email: "cookie@example.com",
      }),
    );

    const cookie = response.headers.get("set-cookie") ?? "";
    // JavaScript must not be able to read the session: the web build's
    // defence against a compromised dependency is that it cannot.
    expect(cookie.toLowerCase()).toContain("httponly");
  });
});

describe("the email code flow", () => {
  async function startEmail(email: string, token?: string): Promise<{ flow: string }> {
    const response = await workerExports.default.fetch("https://opensplit.test/api/identity/email", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ email }),
    });
    expect(response.status).toBe(200);
    return (await response.json()) as { flow: string };
  }

  it("starts a sign-in when nobody is signed in", async () => {
    expect(await startEmail("arriving@example.com")).toEqual({
      flow: "signInPending",
    });
  });

  /**
   * Attaching, not authenticating. Verifying this code keeps the account id,
   * so the groups on this device stay with it.
   */
  it("attaches a free address to a guest session", async () => {
    const guest = await signInAsGuest();

    expect(await startEmail("free@example.com", guest.token)).toEqual({
      flow: "linkPending",
    });
  });

  /**
   * The address belongs to somebody else, so there is nothing to attach it to.
   * Reporting a sign-in is what lets the app warn that continuing leaves this
   * device's ledger behind — rather than discovering it afterwards.
   */
  it("falls back to signing in when the address is already somebody's", async () => {
    await continueWithGoogle(await googleIdToken({ sub: "google-mail", email: "mine@example.com" }));

    const guest = await signInAsGuest();
    expect(await startEmail("mine@example.com", guest.token)).toEqual({
      flow: "signInPending",
    });
  });

  it("refuses a malformed address with the standard error shape", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/api/identity/email", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "not-an-address" }),
    });

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      error: { code: "malformed" },
    });
  });
});
