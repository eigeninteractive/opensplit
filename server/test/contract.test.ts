import { runInDurableObject } from "cloudflare:test";
import { env, exports as workerExports } from "cloudflare:workers";
import { expect, it } from "vitest";

import { makeGroup, ok, stub } from "./group";
import { apiUrl, signInAsGuest } from "./session";

it("unversioned and unavailable APIs return 404 without changing account or group data", async () => {
  const guest = await signInAsGuest();
  const fixture = await makeGroup({ owner: guest.id });
  const id = fixture.groupId;
  const memberId = fixture.ravi.id;
  const d1Snapshot = async () => {
    const tables = ["user", "account", "session", "verification", "profiles", "memberships", "device_tokens", "link_tokens", "purged_groups", "counters"];
    return Promise.all(tables.map(async (table) => (await env.DB.prepare(`SELECT * FROM ${table} ORDER BY 1`).all()).results));
  };
  const groupSnapshot = () =>
    runInDurableObject(stub(id), (_instance, ctx) => {
      const tables = ["meta", "members", "entries", "entry_payers", "entry_shares", "events", "counter", "outbox", "schedule", "invites", "group_link", "tombstone"];
      return tables.map((table) => ctx.storage.sql.exec(`SELECT * FROM ${table} ORDER BY 1`).toArray());
    });
  const beforeD1 = await d1Snapshot();
  const beforeGroup = await groupSnapshot();
  const entry = {
    kind: "expense",
    description: "Old queued edit",
    categoryId: null,
    currency: "INR",
    amountMinor: 100,
    entryDate: "2026-10-14",
    occurredAt: null,
    timeZone: null,
    splitKind: "exact",
    fxRate: null,
    fxSource: null,
    notes: null,
    deletedAt: null,
    baseSeq: null,
    payers: [{ memberId, amountMinor: 100 }],
    shares: [{ memberId, amountMinor: 100, weightMicros: null }],
  };
  const requests: [string, string, object?][] = [
    ["POST", "/api/identity/guest"],
    ["POST", "/api/identity/email", { email: "old-client@example.invalid" }],
    ["POST", "/api/identity/google", { idToken: "old-token" }],
    ["POST", "/api/identity/sign-out"],
    ["POST", "/api/identity/reauth"],
    ["GET", "/api/auth/callback/google"],
    ["POST", "/api/auth/callback/google", { code: "old-code", state: "old-state" }],
    ["GET", "/api/auth/error"],
    ["POST", "/api/sync", { groups: [{ groupId: id, since: 0 }], limit: 200 }],
    ["PUT", `/api/groups/${id}`, { name: "Stale group name", archivedAt: null }],
    ["PUT", `/api/groups/${id}/members/${memberId}`, { displayName: "Stale member", upiVpa: null, leftAt: null }],
    // This expense would still validate under the current contract.
    ["PUT", `/api/groups/${id}/entries/old-expense`, entry],
    ["POST", `/api/groups/${id}/link`],
    ["POST", `/api/groups/${id}/members/${fixture.priya.id}/invite`],
    ["POST", "/api/links/old-token/join", { memberId: null, displayName: null }],
    ["PUT", "/api/profile", { displayName: "Old profile edit" }],
    ["PUT", "/api/devices", { token: "old-push-token", platform: "android" }],
    ["DELETE", "/api/account"],
    ["PUT", `/api/v999/groups/${id}/entries/unknown-version`, entry],
  ];
  for (const [method, path, body] of requests) {
    const response = await workerExports.default.fetch(`https://opensplit.test${path}`, {
      method,
      headers: { Authorization: `Bearer ${guest.token}`, "Content-Type": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    expect(response.status, `${method} ${path}`).toBe(404);
    expect(await response.json()).toMatchObject({ error: { code: "not_found", retry: "permanent" } });
  }
  expect(await d1Snapshot()).toEqual(beforeD1);
  expect(await groupSnapshot()).toEqual(beforeGroup);
  expect(ok(await stub(id).changes(guest.id, 0, 200)).members).toHaveLength(2);
  const session = await workerExports.default.fetch(apiUrl("/identity/session"), { headers: { Authorization: `Bearer ${guest.token}` } });
  expect(await session.json()).toMatchObject({ account: { id: guest.id } });
});

it("unknown operations in the supported contract remain ordinary 404s", async () => {
  const response = await workerExports.default.fetch(apiUrl("/missing-operation"));
  expect(response.status).toBe(404);
  expect(await response.json()).toMatchObject({ error: { code: "not_found" } });
});
