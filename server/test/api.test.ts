import { env, exports as workerExports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";

import type { ApiError } from "../src/schemas/common";
import type { Bootstrap, ChangePage, Entry, Group, Member } from "./api-types";
import { freshId } from "./group";
import { type Guest, signInAsGuest } from "./session";

/**
 * The sync surface over HTTP.
 *
 * The suites before this one reach the Durable Object directly, because that
 * is where every rule lives and a test of a rule should not have to route
 * through a Worker to get at it. This one is the opposite: the rules are
 * assumed, and what is under test is the layer that was added on top of them —
 * whether a request without a session gets anywhere, whether a refusal arrives
 * as the right status with the right retry kind, and whether the validation
 * that happens before a Durable Object is woken actually happens.
 */

const ORIGIN = "https://opensplit.test";

async function call(path: string, guest: Guest | null, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  if (guest) headers.set("Authorization", `Bearer ${guest.token}`);

  return workerExports.default.fetch(`${ORIGIN}${path}`, { ...init, headers });
}

async function json<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

async function makeGroup(guest: Guest, name = "Goa trip") {
  const id = freshId("api");
  const response = await call("/api/groups", guest, {
    method: "POST",
    body: JSON.stringify({ id, name, defaultCurrency: "INR", isDirect: false, simplifyDebts: true, memberId: `${id}-me`, displayName: "Ravi" }),
  });

  expect(response.status).toBe(200);
  return { id, group: await json<Group>(response) };
}

function expense(overrides: Record<string, unknown> = {}) {
  return {
    id: freshId("api-e"),
    kind: "expense",
    description: "",
    categoryId: null,
    currency: "INR",
    amountMinor: 1000,
    entryDate: "2026-09-23",
    occurredAt: null,
    timeZone: null,
    splitKind: "exact",
    fxRate: null,
    fxSource: null,
    notes: null,
    clientKey: null,
    baseSeq: null,
    payers: [],
    shares: [],
    ...overrides,
  };
}

let ravi: Guest;
let zara: Guest;

beforeAll(async () => {
  ravi = await signInAsGuest();
  zara = await signInAsGuest();
});

describe("without a session", () => {
  it("refuses every route in the sync surface", async () => {
    const paths = ["/api/bootstrap", `/api/groups/${freshId()}/changes`];

    for (const path of paths) {
      const response = await call(path, null);
      expect(response.status, path).toBe(401);
      expect((await json<ApiError>(response)).error.code).toBe("no_session");
    }

    const write = await call("/api/groups", null, { method: "POST", body: JSON.stringify({}) });
    expect(write.status).toBe(401);
  });
});

describe("bootstrap", () => {
  it("names the account and the groups it is still in", async () => {
    const { id } = await makeGroup(ravi);
    const body = await json<Bootstrap>(await call("/api/bootstrap", ravi));

    expect(body.profileId).toBe(ravi.id);
    expect(body.isAnonymous).toBe(true);
    expect(body.groupIds).toContain(id);
  });

  it("does not name somebody else's groups", async () => {
    const { id } = await makeGroup(ravi);
    const body = await json<Bootstrap>(await call("/api/bootstrap", zara));

    expect(body.groupIds).not.toContain(id);
  });
});

describe("the change feed", () => {
  it("answers with a cursor, and pages on it", async () => {
    const { id, group } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes?since=0`, ravi));

    expect(page.group?.id).toBe(group.id);
    expect(page.members).toHaveLength(1);
    expect(page.hasMore).toBe(false);

    const nothing = await json<ChangePage>(await call(`/api/groups/${id}/changes?since=${page.seq}`, ravi));
    expect(nothing.seq).toBe(page.seq);
    expect(nothing.members).toHaveLength(0);
  });

  it("refuses a stranger with 403, and says the refusal is permanent", async () => {
    const { id } = await makeGroup(ravi);
    const response = await call(`/api/groups/${id}/changes`, zara);

    expect(response.status).toBe(403);
    const body = await json<ApiError>(response);
    expect(body.error.code).toBe("not_member");
    expect(body.error.retry).toBe("permanent");
  });

  it("tells a device that a group id names nothing, rather than refusing it", async () => {
    const response = await call(`/api/groups/${freshId("ghost")}/changes`, ravi);

    expect(response.status).toBe(404);
    expect((await json<ApiError>(response)).error.code).toBe("no_group");
  });
});

describe("recording an expense over HTTP", () => {
  it("lands, and comes back in the feed", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    const me = page.members[0];
    if (!me) expect.unreachable("The group has no members.");

    const response = await call(`/api/groups/${id}/entries`, ravi, {
      method: "POST",
      body: JSON.stringify(expense({ payers: [{ memberId: me.id, amountMinor: 1000 }], shares: [{ memberId: me.id, amountMinor: 1000, weightMicros: null }] })),
    });

    expect(response.status).toBe(200);
    const entry = await json<Entry>(response);
    expect(entry.amountMinor).toBe(1000);
    expect(entry.createdBy).toBe(me.id);

    const after = await json<ChangePage>(await call(`/api/groups/${id}/changes?since=${page.seq}`, ravi));
    expect(after.entries.map((row) => row.id)).toContain(entry.id);
  });

  /**
   * 422 rather than 400, because the request is well formed and the *expense*
   * is not. The distinction matters to a device deciding whether it sent
   * something malformed or computed a split wrongly.
   */
  it("is refused with 422 when it does not add up", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    const me = page.members[0];
    if (!me) expect.unreachable("The group has no members.");

    const response = await call(`/api/groups/${id}/entries`, ravi, {
      method: "POST",
      body: JSON.stringify(expense({ payers: [{ memberId: me.id, amountMinor: 999 }], shares: [{ memberId: me.id, amountMinor: 1000, weightMicros: null }] })),
    });

    expect(response.status).toBe(422);
    const body = await json<ApiError>(response);
    expect(body.error.code).toBe("unbalanced");
    expect(body.error.retry).toBe("permanent");
  });

  /**
   * The one refusal a device should act on by re-reading and composing again,
   * and the only one of six 409s that says so.
   */
  it("is refused with 409 and retry 'stale' when somebody else moved the money", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    const me = page.members[0];
    if (!me) expect.unreachable("The group has no members.");

    const body = (amount: number) => expense({ id: entryId, amountMinor: amount, payers: [{ memberId: me.id, amountMinor: amount }], shares: [{ memberId: me.id, amountMinor: amount, weightMicros: null }] });
    const entryId = freshId("api-e");

    const first = await json<Entry>(await call(`/api/groups/${id}/entries`, ravi, { method: "POST", body: JSON.stringify(body(1000)) }));
    await call(`/api/groups/${id}/entries`, ravi, { method: "POST", body: JSON.stringify(body(2000)) });

    const stale = await call(`/api/groups/${id}/entries`, ravi, { method: "POST", body: JSON.stringify({ ...body(1500), baseSeq: first.seq }) });

    expect(stale.status).toBe(409);
    const refusal = await json<ApiError>(stale);
    expect(refusal.error.code).toBe("stale_base");
    expect(refusal.error.retry).toBe("stale");
  });

  it("is refused with 400 before a Durable Object is ever woken, when the shape is wrong", async () => {
    const { id } = await makeGroup(ravi);
    const response = await call(`/api/groups/${id}/entries`, ravi, {
      method: "POST",
      body: JSON.stringify({ id: freshId("api-e"), currency: "rupees", amountMinor: -5, entryDate: "yesterday", payers: [], shares: [] }),
    });

    expect(response.status).toBe(400);
    expect((await json<ApiError>(response)).error.code).toBe("malformed");
  });

  it("keeps when and where it happened, and holds the date to that moment's own day", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    const me = page.members[0];
    if (!me) expect.unreachable("The group has no members.");
    const post = (moment: Record<string, unknown>) =>
      call(`/api/groups/${id}/entries`, ravi, {
        method: "POST",
        body: JSON.stringify(expense({ payers: [{ memberId: me.id, amountMinor: 1000 }], shares: [{ memberId: me.id, amountMinor: 1000, weightMicros: null }], ...moment })),
      });

    // 1 a.m. in Goa is still the previous evening in UTC.
    const snack = { occurredAt: "2026-09-23T19:30:00.000Z", timeZone: "Asia/Kolkata" };
    expect((await post({ ...snack, entryDate: "2026-09-23" })).status).toBe(400);

    const stored = await json<Entry>(await post({ ...snack, entryDate: "2026-09-24" }));
    expect(stored).toMatchObject({ ...snack, entryDate: "2026-09-24" });

    expect((await post({ occurredAt: snack.occurredAt, timeZone: null, entryDate: "2026-09-24" })).status).toBe(400);
    expect((await post({ ...snack, timeZone: "Goa/Beach", entryDate: "2026-09-24" })).status).toBe(400);
  });

  it("soft-deletes, and refuses a delete carrying no version at all", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    const me = page.members[0];
    if (!me) expect.unreachable("The group has no members.");

    const entry = await json<Entry>(
      await call(`/api/groups/${id}/entries`, ravi, {
        method: "POST",
        body: JSON.stringify(expense({ payers: [{ memberId: me.id, amountMinor: 1000 }], shares: [{ memberId: me.id, amountMinor: 1000, weightMicros: null }] })),
      }),
    );

    // Deleting always moves money, so the version is required rather than
    // optional — a missing one is a malformed request, not a licence.
    const bare = await call(`/api/groups/${id}/entries/${entry.id}`, ravi, { method: "DELETE" });
    expect(bare.status).toBe(400);

    const deleted = await call(`/api/groups/${id}/entries/${entry.id}?baseSeq=${entry.seq}`, ravi, { method: "DELETE" });
    expect(deleted.status).toBe(200);
    expect((await json<Entry>(deleted)).deletedAt).not.toBeNull();
  });
});

describe("the roster over HTTP", () => {
  it("adds a placeholder and edits it", async () => {
    const { id } = await makeGroup(ravi);
    const memberId = freshId("api-m");

    const added = await call(`/api/groups/${id}/members`, ravi, { method: "POST", body: JSON.stringify({ id: memberId, displayName: "Priya", upiVpa: null }) });
    expect(added.status).toBe(200);
    expect((await json<Member>(added)).profileId).toBeNull();

    const patched = await call(`/api/groups/${id}/members/${memberId}`, ravi, { method: "PUT", body: JSON.stringify({ displayName: "Priya", upiVpa: "priya@okaxis", leftAt: null }) });
    expect(patched.status).toBe(200);
    expect((await json<Member>(patched)).upiVpa).toBe("priya@okaxis");
  });

  it("refuses a payment handle that is not one, before the object sees it", async () => {
    const { id } = await makeGroup(ravi);
    const memberId = freshId("api-m");
    await call(`/api/groups/${id}/members`, ravi, { method: "POST", body: JSON.stringify({ id: memberId, displayName: "Priya", upiVpa: null }) });

    const response = await call(`/api/groups/${id}/members/${memberId}`, ravi, { method: "PUT", body: JSON.stringify({ displayName: "Priya", upiVpa: "not a handle", leftAt: null }) });
    expect(response.status).toBe(400);
  });

  it("renames a group, and refuses a blank name", async () => {
    const { id } = await makeGroup(ravi);

    const renamed = await call(`/api/groups/${id}`, ravi, { method: "PUT", body: JSON.stringify({ name: "Goa, take two", simplifyDebts: true, archivedAt: null }) });
    expect((await json<Group>(renamed)).name).toBe("Goa, take two");

    const blank = await call(`/api/groups/${id}`, ravi, { method: "PUT", body: JSON.stringify({ name: "   ", simplifyDebts: true, archivedAt: null }) });
    expect(blank.status).toBe(400);
  });
});

describe("which group a page is about", () => {
  /**
   * Stated by the server rather than assumed from the request. A device writes
   * these rows into a local database that is multi-group, so it needs the id —
   * and taking it from the response is what makes a page answering for the
   * wrong group detectable instead of silently merged into the right one.
   */
  it("is on the page, and not repeated on every row", async () => {
    const { id } = await makeGroup(ravi);
    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));

    expect(page.groupId).toBe(id);

    const rows = [...page.members, ...page.entries, ...page.events] as Record<string, unknown>[];
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) expect(row).not.toHaveProperty("groupId");
  });

  it("is still stated by a group that has been collected", async () => {
    const { id } = await makeGroup(ravi);
    await env.GROUP.getByName(id).runUpkeep(Date.now() + 800 * 24 * 60 * 60 * 1000);

    const page = await json<ChangePage>(await call(`/api/groups/${id}/changes`, ravi));
    expect(page.groupId).toBe(id);
    expect(page.purgedAt).not.toBeNull();
    expect(page.group).toBeNull();
  });
});
