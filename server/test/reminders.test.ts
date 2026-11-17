import { env, exports as workerExports } from "cloudflare:workers";
import { drizzle } from "drizzle-orm/d1";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { defaultGroupLook } from "../src/db/appearance";
import { deviceTokens } from "../src/db/d1/schema";
import type { ApiError } from "../src/schemas/common";
import type { GroupLink, GroupSeen, Joined, Reminder } from "../src/schemas/ledger";
import { TEST_KEY } from "./fcm-key";
import { freshId } from "./group";
import { apiUrl, type Guest, pull, signInAsGuest } from "./session";

/** Asking to be paid, and remembering what an account has read. */

async function call(path: string, guest: Guest, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Authorization", `Bearer ${guest.token}`);
  return workerExports.default.fetch(apiUrl(path), { ...init, headers });
}

async function json<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

interface Trip {
  groupId: string;
  /** Ravi's own place: he made the group. */
  raviId: string;
  /** Zara's place: she joined by link, with an account. */
  zaraId: string;
  /** Priya's place: a name Ravi added, with no account behind it. */
  priyaId: string;
}

/** A group of three, in which Zara and Priya each owe Ravi a third of dinner. */
async function makeTrip(): Promise<Trip> {
  const groupId = freshId("rem");
  const raviId = `${groupId}-ravi`;
  const priyaId = `${groupId}-priya`;
  const made = await call(`/groups/${groupId}`, ravi, {
    method: "PUT",
    body: JSON.stringify({ name: "Goa trip", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, baseSeq: null, ...defaultGroupLook, creatorId: raviId, creatorName: "Ravi" }),
  });
  expect(made.status).toBe(200);
  const added = await call(`/groups/${groupId}/members/${priyaId}`, ravi, { method: "PUT", body: JSON.stringify({ displayName: "Priya", upiVpa: null, leftAt: null, baseSeq: null }) });
  expect(added.status).toBe(200);

  const link = await json<GroupLink>(await call(`/groups/${groupId}/link`, ravi, { method: "POST" }));
  const joined = await call(`/links/${link.token}/join`, zara, { method: "POST", body: JSON.stringify({ memberId: null, displayName: "Zara" }) });
  expect(joined.status).toBe(200);
  const zaraId = (await json<Joined>(joined)).member.id;

  const dinner = await call(`/groups/${groupId}/entries/${freshId("rem-e")}`, ravi, {
    method: "PUT",
    body: JSON.stringify({
      kind: "expense",
      description: "Dinner",
      categoryId: null,
      currency: "INR",
      amountMinor: 3000,
      entryDate: "2026-09-23",
      occurredAt: null,
      timeZone: null,
      splitKind: "exact",
      fxRate: null,
      fxSource: null,
      notes: null,
      deletedAt: null,
      baseSeq: null,
      payers: [{ memberId: raviId, amountMinor: 3000 }],
      shares: [raviId, zaraId, priyaId].map((memberId) => ({ memberId, amountMinor: 1000, weightMicros: 0 })),
    }),
  });
  expect(dinner.status).toBe(200);
  return { groupId, raviId, zaraId, priyaId };
}

function remind(trip: Trip, from: Guest, memberId: string, currency = "INR") {
  return call(`/groups/${trip.groupId}/reminders`, from, { method: "POST", body: JSON.stringify({ memberId, currency }) });
}

async function registerDevice(profileId: string, token: string) {
  await drizzle(env.DB).insert(deviceTokens).values({ token, profileId, platform: "android", updatedAt: new Date().toISOString() });
}

/** Every message FCM was asked to send, and the registration it went to. */
let sent: { token: string; data: Record<string, string> }[] = [];
let ravi: Guest;
let zara: Guest;

beforeAll(async () => {
  env.FCM_PROJECT_ID = "opensplit-test";
  env.FCM_SERVICE_ACCOUNT = JSON.stringify({ client_email: "push@opensplit.test", private_key: TEST_KEY });
  ravi = await signInAsGuest();
  zara = await signInAsGuest();
});

beforeEach(() => {
  sent = [];
  const real = globalThis.fetch;
  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    if (url.includes("oauth2.googleapis.com")) return Response.json({ access_token: "stub-token", expires_in: 3600 });
    if (url.includes("fcm.googleapis.com")) {
      const body = JSON.parse(String(init?.body)) as { message: { token: string; data: Record<string, string> } };
      sent.push({ token: body.message.token, data: body.message.data });
      return Response.json({ name: "sent" });
    }
    return real(input, init);
  });
});

afterEach(async () => {
  await new Promise((resolve) => setTimeout(resolve, 0));
  await drizzle(env.DB).delete(deviceTokens);
  vi.unstubAllGlobals();
});

describe("reminding somebody who owes you", () => {
  it("wakes their devices, and nobody else's, with who is asking and in which currency", async () => {
    const trip = await makeTrip();
    await registerDevice(zara.id, "device-zara");
    await registerDevice(ravi.id, "device-ravi");
    sent = [];

    const response = await remind(trip, ravi, trip.zaraId);

    expect(response.status).toBe(200);
    const reminder = await json<Reminder>(response);
    expect(reminder.outcome).toBe("sent");
    expect(reminder.sentAt).not.toBeNull();
    expect(sent.map((message) => message.token)).toEqual(["device-zara"]);
    expect(sent[0]?.data).toMatchObject({ groupId: trip.groupId, kind: "reminder", subjectId: trip.raviId, currency: "INR" });
  });

  it("sends one a day, and says when the first went", async () => {
    const trip = await makeTrip();
    await registerDevice(zara.id, "device-zara");
    const first = await json<Reminder>(await remind(trip, ravi, trip.zaraId));
    sent = [];

    const second = await json<Reminder>(await remind(trip, ravi, trip.zaraId));

    expect(second).toEqual({ outcome: "already_reminded", sentAt: first.sentAt });
    expect(sent).toEqual([]);
  });

  it("says so when they have no device to notify, and does not count it", async () => {
    const trip = await makeTrip();

    expect(await json<Reminder>(await remind(trip, ravi, trip.zaraId))).toEqual({ outcome: "unreachable", sentAt: null });

    await registerDevice(zara.id, "device-zara");
    expect((await json<Reminder>(await remind(trip, ravi, trip.zaraId))).outcome).toBe("sent");
  });

  it("refuses the one who owes, a name with no account, and yourself", async () => {
    const trip = await makeTrip();
    await registerDevice(ravi.id, "device-ravi");
    sent = [];

    for (const [from, memberId] of [
      [zara, trip.raviId],
      [ravi, trip.priyaId],
      [ravi, trip.raviId],
    ] as const) {
      const response = await remind(trip, from, memberId);
      expect(response.status).toBe(403);
      expect((await json<ApiError>(response)).error.code).toBe("forbidden");
    }
    expect(sent).toEqual([]);
  });

  it("refuses a currency in which nothing is owed, and anybody outside the group", async () => {
    const trip = await makeTrip();
    const stranger = await signInAsGuest();

    expect((await remind(trip, ravi, trip.zaraId, "EUR")).status).toBe(403);
    const outside = await remind(trip, stranger, trip.zaraId);
    expect(outside.status).toBe(403);
    expect((await json<ApiError>(outside)).error.code).toBe("not_member");
  });
});

describe("how far an account has read a group", () => {
  function putSeen(groupId: string, guest: Guest, seenAt: string) {
    return call(`/groups/${groupId}/seen`, guest, { method: "PUT", body: JSON.stringify({ seenAt }) });
  }

  it("is told to every device in the next pull, and to nobody else", async () => {
    const trip = await makeTrip();
    expect((await pull(ravi, [])).seen.filter((seen) => seen.groupId === trip.groupId)).toEqual([]);

    const response = await putSeen(trip.groupId, ravi, "2026-09-23T10:00:00.000Z");

    expect(response.status).toBe(200);
    expect(await json<GroupSeen>(response)).toEqual({ groupId: trip.groupId, seenAt: "2026-09-23T10:00:00.000Z" });
    expect((await pull(ravi, [])).seen).toContainEqual({ groupId: trip.groupId, seenAt: "2026-09-23T10:00:00.000Z" });
    expect((await pull(zara, [])).seen.filter((seen) => seen.groupId === trip.groupId)).toEqual([]);
  });

  it("only moves forward, and never past the server's clock", async () => {
    const trip = await makeTrip();
    await putSeen(trip.groupId, ravi, "2026-09-23T10:00:00.000Z");

    const earlier = await json<GroupSeen>(await putSeen(trip.groupId, ravi, "2026-09-22T10:00:00.000Z"));
    expect(earlier.seenAt).toBe("2026-09-23T10:00:00.000Z");

    const future = await json<GroupSeen>(await putSeen(trip.groupId, ravi, "2999-01-01T00:00:00.000Z"));
    expect(future.seenAt > "2026-09-23T10:00:00.000Z").toBe(true);
    expect(future.seenAt <= new Date().toISOString()).toBe(true);
  });

  it("refuses somebody who is not in the group", async () => {
    const trip = await makeTrip();
    const stranger = await signInAsGuest();

    const response = await putSeen(trip.groupId, stranger, "2026-09-23T10:00:00.000Z");

    expect(response.status).toBe(403);
    expect((await json<ApiError>(response)).error.code).toBe("not_member");
  });
});
