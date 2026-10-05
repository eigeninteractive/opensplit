import { env, exports as workerExports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { IdentityOutcome } from "../src/schemas/identity";
import { googleIdToken } from "./google";
import { randomIp, signInAsGuest } from "./session";

/**
 * A session lasts a year, so holding one is not proof enough to delete the
 * account behind it: an account with an address confirms with a fresh code.
 */

const ORIGIN = "https://opensplit.test";

function call(path: string, token: string, init: { method: string; body?: unknown }) {
  return workerExports.default.fetch(`${ORIGIN}/api${path}`, {
    method: init.method,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, "CF-Connecting-IP": randomIp() },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

async function googleAccount(sub: string): Promise<{ id: string; token: string; email: string }> {
  const email = `${sub}@example.com`;
  const response = await workerExports.default.fetch(`${ORIGIN}/api/identity/google`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken: await googleIdToken({ sub, email }), nonce: null, allowSignIn: true }),
  });
  const outcome = (await response.json()) as IdentityOutcome;
  if (!outcome.token) throw new Error("No bearer token");
  return { id: outcome.account.id, token: outcome.token, email };
}

/** As if the session was signed in long ago and has only been used since. */
async function age(userId: string) {
  await env.DB.prepare("update session set created_at = ? where user_id = ?")
    .bind(Date.now() - 60 * 60 * 1000, userId)
    .run();
}

/** The code the local sender printed, which is where a real one would be emailed. */
function lastCode(log: ReturnType<typeof vi.spyOn>): string {
  const printed = log.mock.calls.map((args: unknown[]) => String(args[0])).join("\n");
  const codes = [...printed.matchAll(/code is (\d+)/g)];
  const code = codes.at(-1)?.[1];
  if (!code) throw new Error("No code was sent");
  return code;
}

afterEach(() => vi.restoreAllMocks());

describe("deleting an account with an address", () => {
  it("goes ahead straight after signing in", async () => {
    const account = await googleAccount("reauth-fresh");
    expect((await call("/account", account.token, { method: "DELETE" })).status).toBe(200);
  });

  it("asks for confirmation once the sign-in is old", async () => {
    const account = await googleAccount("reauth-stale");
    await age(account.id);

    const response = await call("/account", account.token, { method: "DELETE" });
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({ error: { code: "reauth_required" } });
    expect(await env.DB.prepare("select id from user where id = ?").bind(account.id).first()).not.toBeNull();
  });

  it("goes ahead once a code sent to the account's own address is entered", async () => {
    const log = vi.spyOn(console, "log");
    const account = await googleAccount("reauth-confirm");
    await age(account.id);

    const started = await call("/identity/reauth", account.token, { method: "POST" });
    expect(started.status).toBe(200);
    expect(await started.json()).toEqual({ email: account.email });

    const verified = await call("/identity/reauth/verify", account.token, { method: "POST", body: { code: lastCode(log) } });
    expect(verified.status).toBe(200);
    const session = (await verified.json()) as { account: { id: string }; token: string };
    expect(session.account.id).toBe(account.id);
    expect(session.token).not.toBe(account.token);

    // Confirming leaves one session, not two: the old one is over.
    const old = await call("/identity/session", account.token, { method: "GET" });
    expect(await old.json()).toMatchObject({ account: null });

    expect((await call("/account", session.token, { method: "DELETE" })).status).toBe(200);
  });

  it("refuses a wrong code, and keeps the session it had", async () => {
    const account = await googleAccount("reauth-wrong");
    await call("/identity/reauth", account.token, { method: "POST" });

    const verified = await call("/identity/reauth/verify", account.token, { method: "POST", body: { code: "00000000" } });
    expect(verified.status).toBe(400);

    const still = await call("/identity/session", account.token, { method: "GET" });
    expect(await still.json()).toMatchObject({ account: { id: account.id } });
  });
});

/**
 * A session somebody else got hold of must not be able to point the account
 * at their own address or Google account: after that, the confirmation above
 * would go to them.
 */
describe("changing how an account with an address signs in", () => {
  it("is refused for an address once the sign-in is old", async () => {
    const account = await googleAccount("relink-stale-email");
    await age(account.id);

    const response = await call("/identity/email", account.token, { method: "POST", body: { email: "thief@example.com" } });
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({ error: { code: "reauth_required" } });
  });

  it("is refused for a Google account once the sign-in is old", async () => {
    const account = await googleAccount("relink-stale-google");
    await age(account.id);

    const linked = await call("/identity/google", account.token, { method: "POST", body: { idToken: await googleIdToken({ sub: "thief", email: "thief@example.com" }), nonce: null, allowSignIn: false } });
    expect(linked.status).toBe(403);
    expect(await linked.json()).toMatchObject({ error: { code: "reauth_required" } });

    const redirect = await call("/identity/google/redirect", account.token, { method: "POST", body: { callbackUrl: "http://localhost:8787/app/welcome", allowSignIn: false } });
    expect(redirect.status).toBe(403);
  });

  it("still lets an old session sign in to a different account", async () => {
    const account = await googleAccount("relink-stale-switch");
    await age(account.id);

    const response = await call("/identity/google", account.token, { method: "POST", body: { idToken: await googleIdToken({ sub: "relink-other", email: "other@example.com" }), nonce: null, allowSignIn: true } });
    expect(response.status).toBe(200);
    const outcome = (await response.json()) as IdentityOutcome;
    expect(outcome.outcome).toBe("replaced");
    expect(outcome.strandedUserId).toBe(account.id);
  });

  it("goes ahead straight after signing in", async () => {
    const account = await googleAccount("relink-fresh");
    const response = await call("/identity/email", account.token, { method: "POST", body: { email: "relink-fresh-new@example.com" } });
    expect(await response.json()).toEqual({ flow: "linkPending" });
  });
});

describe("a guest", () => {
  it("attaches an address however old the session, since that is how it keeps its groups", async () => {
    const guest = await signInAsGuest();
    await age(guest.id);

    const response = await call("/identity/email", guest.token, { method: "POST", body: { email: "old-guest@example.com" } });
    expect(await response.json()).toEqual({ flow: "linkPending" });
  });

  /** Nothing identifies a guest but the session, so there is nothing more to ask for. */
  it("deletes without confirming, however old the session", async () => {
    const guest = await signInAsGuest();
    await age(guest.id);

    expect((await call("/account", guest.token, { method: "DELETE" })).status).toBe(200);
  });

  it("is not sent a code", async () => {
    const guest = await signInAsGuest();
    const response = await call("/identity/reauth", guest.token, { method: "POST" });

    expect(response.status).toBe(400);
  });
});

describe("a session", () => {
  it("lasts a year from when it was last used", async () => {
    const guest = await signInAsGuest();
    const row = await env.DB.prepare("select expires_at from session where user_id = ?").bind(guest.id).first<{ expires_at: number }>();
    const days = ((row?.expires_at ?? 0) - Date.now()) / (24 * 60 * 60 * 1000);

    expect(days).toBeGreaterThan(364);
    expect(days).toBeLessThanOrEqual(365);
  });
});
