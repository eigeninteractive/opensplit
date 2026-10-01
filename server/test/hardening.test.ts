import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import { randomIp, signInAsGuest } from "./session";

/** The brakes on the doors anybody can knock on, and the refusals that must say the right thing. */

const ORIGIN = "https://opensplit.test";

function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return workerExports.default.fetch(`${ORIGIN}/api${path}`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
}

async function errorOf(response: Response) {
  return ((await response.json()) as { error: { code: string; retry: string } }).error;
}

describe("rate limits", () => {
  it("stop one address starting guest after guest", async () => {
    const ip = randomIp();
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 6; attempt++) statuses.push((await post("/identity/guest", {}, { "CF-Connecting-IP": ip })).status);

    expect(statuses).toEqual([200, 200, 200, 200, 200, 429]);
  });

  it("say so in the envelope, as something to try again later", async () => {
    const ip = randomIp();
    for (let attempt = 0; attempt < 5; attempt++) await post("/identity/guest", {}, { "CF-Connecting-IP": ip });

    const refused = await post("/identity/guest", {}, { "CF-Connecting-IP": ip });
    expect(await errorOf(refused)).toMatchObject({ code: "rate_limited", retry: "transient" });
  });

  it("stop one inbox being sent code after code, whoever asks", async () => {
    const address = `${crypto.randomUUID()}@example.com`;
    const statuses: number[] = [];
    // A different address each time, so only the per-inbox limit can be what refuses.
    for (let attempt = 0; attempt < 4; attempt++) statuses.push((await post("/identity/email", { email: address }, { "CF-Connecting-IP": randomIp() })).status);

    expect(statuses).toEqual([200, 200, 200, 429]);
  });

  it("stop one address guessing codes", async () => {
    const ip = randomIp();
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 11; attempt++) {
      statuses.push((await post("/identity/email/verify", { email: `${crypto.randomUUID()}@example.com`, code: "00000000", flow: "signInPending" }, { "CF-Connecting-IP": ip })).status);
    }

    expect(statuses.at(-1)).toBe(429);
    expect(statuses.slice(0, 10)).not.toContain(429);
  });
});

describe("asking for a rate backfill", () => {
  it("needs a session", async () => {
    const response = await post("/fx/backfill", { asOf: "2026-08-14", currency: "INR" });
    expect(response.status).toBe(401);
  });

  it("refuses a day before any rate exists", async () => {
    const guest = await signInAsGuest();
    const response = await post("/fx/backfill", { asOf: "1990-01-01", currency: "INR" }, { Authorization: `Bearer ${guest.token}` });

    expect(response.status).toBe(400);
    expect((await errorOf(response)).code).toBe("malformed");
  });

  it("is limited per account", async () => {
    const guest = await signInAsGuest();
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 11; attempt++) statuses.push((await post("/fx/backfill", { asOf: "2026-08-14", currency: "INR" }, { Authorization: `Bearer ${guest.token}` })).status);

    expect(statuses.at(-1)).toBe(429);
    expect(statuses.slice(0, 10)).not.toContain(429);
  });
});

describe("the Google redirect", () => {
  /** Google sends the browser to this address even when sign-in fails, so another site here is an open redirect. */
  it("refuses to send the browser back anywhere but this site", async () => {
    const response = await post("/identity/google/redirect", { callbackUrl: "https://evil.example/phish", allowSignIn: true });

    expect(response.status).toBe(400);
    expect((await errorOf(response)).code).toBe("malformed");
  });
});

describe("an expense with half an exchange rate", () => {
  it("is refused as malformed, not crashed on", async () => {
    const guest = await signInAsGuest();
    const groupId = crypto.randomUUID();
    const auth = { Authorization: `Bearer ${guest.token}` };
    const put = (path: string, body: unknown) => workerExports.default.fetch(`${ORIGIN}/api${path}`, { method: "PUT", headers: { "Content-Type": "application/json", ...auth }, body: JSON.stringify(body) });

    expect((await put(`/groups/${groupId}`, { name: "Trip", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, archivedAt: null, creatorId: "me", creatorName: "Me" })).status).toBe(200);

    const response = await put(`/groups/${groupId}/entries/e1`, {
      kind: "expense",
      description: "Dinner",
      categoryId: null,
      currency: "INR",
      amountMinor: 100,
      entryDate: "2026-09-23",
      occurredAt: null,
      timeZone: null,
      splitKind: "equal",
      fxRate: 1.5,
      fxSource: null,
      notes: null,
      deletedAt: null,
      baseSeq: null,
      payers: [{ memberId: "me", amountMinor: 100 }],
      shares: [{ memberId: "me", amountMinor: 100, weightMicros: 1_000_000 }],
    });

    expect(response.status).toBe(400);
    expect((await errorOf(response)).code).toBe("malformed");
  });
});

describe("a crash", () => {
  /** A device sets aside a write told "permanent" until somebody retries it by hand; a crash says nothing about that. */
  it("tells the device to try again later", async () => {
    const guest = await signInAsGuest();
    await env.DB.prepare("alter table profiles rename to profiles_away").run();
    try {
      const response = await workerExports.default.fetch(`${ORIGIN}/api/profile`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${guest.token}` },
        body: JSON.stringify({ displayName: "Asha", upiVpa: null }),
      });

      expect(response.status).toBe(500);
      expect(await errorOf(response)).toMatchObject({ code: "internal", retry: "transient" });
    } finally {
      await env.DB.prepare("alter table profiles_away rename to profiles").run();
    }
  });
});
