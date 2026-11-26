import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { deviceTokens } from "../src/db/d1/schema";
import { TEST_KEY } from "./fcm-key";
import { BY_INVITE, editGroup, editMember, evenly, freshId, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, saveEntry, stub, ZARA } from "./group";

/** Who gets woken, and who does not. */

const FCM_HOST = "fcm.googleapis.com";
const TOKEN_HOST = "oauth2.googleapis.com";

/** Every message FCM was asked to send, and the registration it went to. */
interface Sent {
  token: string;
  data: Record<string, string>;
}

let sent: Sent[] = [];
let failWith: ((token: string) => Response | undefined) | undefined;

/** Registers a push token for an account, the way the app does on launch. */
async function registerDevice(profileId: string, token: string) {
  await drizzle(env.DB).insert(deviceTokens).values({ token, profileId, platform: "android", updatedAt: new Date().toISOString() }).onConflictDoUpdate({ target: deviceTokens.token, set: { profileId } });
}

/** Lets the queued `waitUntil` work finish. */
const settled = () => new Promise((resolve) => setTimeout(resolve, 0));

/** Draws a line under the setup. */
async function arranged() {
  await settled();
  sent.length = 0;
}

beforeAll(() => {
  env.FCM_PROJECT_ID = "opensplit-test";
  // A throwaway key, generated for this file and used nowhere else.
  env.FCM_SERVICE_ACCOUNT = JSON.stringify({ client_email: "push@opensplit.test", private_key: TEST_KEY });
});

/** The stub is installed for every test, including the setup. */
beforeEach(() => {
  sent = [];
  failWith = undefined;

  vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

    if (url.includes(TOKEN_HOST)) {
      return Response.json({ access_token: "stub-token", expires_in: 3600 });
    }

    if (url.includes(FCM_HOST)) {
      const body = JSON.parse(String(init?.body)) as { message: { token: string; data: Record<string, string> } };
      const failure = failWith?.(body.message.token);
      if (failure) return failure;

      sent.push({ token: body.message.token, data: body.message.data });
      return Response.json({ name: "sent" });
    }

    return new Response("unexpected", { status: 500 });
  });
});

/** Registrations do not survive a test. */
afterEach(async () => {
  await settled();
  await drizzle(env.DB).delete(deviceTokens);
  vi.unstubAllGlobals();
});

describe("recording an expense", () => {
  it("wakes the other member and not the one who did it", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(RAVI, "device-ravi");
    await registerDevice(PRIYA, "device-priya");

    await arranged();
    ok(await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));
    await settled();

    // The actor is excluded, not the author.
    expect(sent.map((message) => message.token)).toEqual(["device-priya"]);
  });

  it("carries ids and nothing else", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-priya");

    await arranged();
    const entryId = freshId("e");
    ok(await saveEntry(stub(fixture.groupId), evenly(entryId, fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));
    await settled();

    // No amount, no description, no name.
    expect(sent[0]?.data).toEqual({
      kind: "entry",
      eventId: expect.any(String),
      subjectId: entryId,
      groupId: fixture.groupId,
    });
  });

  it("wakes the author when somebody else edits their expense", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(RAVI, "device-ravi");
    await registerDevice(PRIYA, "device-priya");

    const entryId = freshId("e");
    const entry = ok(await saveEntry(stub(fixture.groupId), evenly(entryId, fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));

    await arranged();
    ok(await saveEntry(stub(fixture.groupId), { ...evenly(entryId, fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 60000), baseSeq: entry.seq }, PRIYA));
    await settled();

    expect(sent.map((message) => message.token)).toEqual(["device-ravi"]);
  });
});

describe("what does not wake a device", () => {
  it("a rename or a link being minted", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-priya");

    await arranged();
    const object = stub(fixture.groupId);

    ok(await editGroup(fixture.groupId, RAVI, { name: "Goa, again" }));
    ok(await object.createLink(RAVI));
    await settled();

    // These belong in the activity feed, which is read on purpose, rather than
    // on a lock screen.
    expect(sent).toEqual([]);
  });

  it("a change in a group where nobody else has an account", async () => {
    const fixture = await makeGroup();
    await registerDevice(RAVI, "device-ravi-solo");

    await arranged();
    ok(await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));
    await settled();

    // Priya is a placeholder: a real person with no account, and therefore no
    // device. The only other member is the actor.
    expect(sent).toEqual([]);
  });

  it("a retried push that changes nothing", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-priya");
    const expense = evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000);
    ok(await saveEntry(stub(fixture.groupId), expense, RAVI));

    // The response was lost and the outbox sends the same row again.
    await arranged();
    ok(await saveEntry(stub(fixture.groupId), expense, RAVI));
    await settled();

    expect(sent).toEqual([]);
  });

  it("a change in a group somebody has left", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-priya-left");

    ok(await editMember(fixture.groupId, fixture.priya.id, PRIYA, { leftAt: new Date().toISOString() }));

    await arranged();
    ok(await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id], 10000), RAVI));
    await settled();

    // Somebody who has left has stopped reading this group. The feed cuts them
    // off at the change that recorded their leaving, and so does this.
    expect(sent).toEqual([]);
  });

  it("a refused write", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-priya-refused");

    await arranged();
    // Does not add up, so nothing is committed and nothing happened.
    const refused = await saveEntry(stub(fixture.groupId), { ...evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), amountMinor: 99999 }, RAVI);
    await settled();

    expect(refused.ok).toBe(false);
    expect(sent).toEqual([]);
  });
});

describe("settlement notifications", () => {
  it("wakes only participants who did not record the payment", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const group = stub(groupId);
    const link = ok(await group.createLink(RAVI));
    ok(await group.join(link.token, ZARA, { memberId: null, displayName: "Zara" }));
    await registerDevice(RAVI, "payer-recorder");
    await registerDevice(PRIYA, "payee");
    await registerDevice(ZARA, "other-member");
    await arranged();

    ok(await saveEntry(group, { ...evenly(freshId("e"), ravi.id, [priya.id], 500), kind: "settlement" }, RAVI));
    await settled();
    expect(sent.map(({ token }) => token)).toEqual(["payee"]);
    expect(sent[0]?.data.entryKind).toBe("settlement");

    await arranged();
    ok(await saveEntry(group, { ...evenly(freshId("e"), ravi.id, [priya.id], 500), kind: "settlement" }, ZARA));
    await settled();
    expect(sent.map(({ token }) => token).sort()).toEqual(["payee", "payer-recorder"]);
  });

  it("reminds all current debtors on the same weekly check", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const group = stub(groupId);
    const link = ok(await group.createLink(RAVI));
    const { member: zara } = ok(await group.join(link.token, ZARA, { memberId: null, displayName: "Zara" }));
    await registerDevice(RAVI, "creditor");
    await registerDevice(PRIYA, "first-debtor");
    await registerDevice(ZARA, "second-debtor");
    ok(await saveEntry(group, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 500), RAVI));
    ok(await saveEntry(group, evenly(freshId("e"), ravi.id, [ravi.id, zara.id], 500), RAVI));
    await arranged();
    const makeDue = () =>
      runInDurableObject(group, async (_instance, state) => {
        state.storage.sql.exec("update schedule set due_at = ? where name = 'settlement-nudge'", Date.now() - 1);
      });

    await makeDue();
    expect(await runDurableObjectAlarm(group)).toBe(true);
    await settled();
    const nudge = (token: string) => ({ token, data: { kind: "settlement_nudge", groupId, eventId: expect.any(String), subjectId: groupId } });
    expect(sent).toEqual(expect.arrayContaining([nudge("first-debtor"), nudge("second-debtor")]));
    expect(sent).toHaveLength(2);

    // A retry or earlier outbox alarm cannot send again before the next deadline.
    expect(await runDurableObjectAlarm(group)).toBe(true);
    await settled();
    expect(sent).toHaveLength(2);

    ok(await saveEntry(group, { ...evenly(freshId("e"), priya.id, [ravi.id], 250), kind: "settlement" }, RAVI));
    await arranged();
    await makeDue();
    expect(await runDurableObjectAlarm(group)).toBe(true);
    await settled();
    expect(sent).toEqual([nudge("second-debtor")]);

    await drizzle(env.DB).delete(deviceTokens).where(eq(deviceTokens.token, "second-debtor"));
    await arranged();
    await makeDue();
    expect(await runDurableObjectAlarm(group)).toBe(true);
    await settled();
    expect(sent).toEqual([]);
  });
});

describe("somebody arriving", () => {
  it("wakes the people already there, and not the arrival", async () => {
    const fixture = await makeGroup();
    await registerDevice(RAVI, "device-ravi-join");
    await registerDevice(ZARA, "device-zara-join");

    const invite = ok(await stub(fixture.groupId).createInvite(fixture.priya.id, RAVI));

    await arranged();
    ok(await stub(fixture.groupId).join(invite.token, ZARA, BY_INVITE));
    await settled();

    // Nobody did this to the arrival, and they do not need telling they just
    // joined — the app has already navigated them into the group.
    expect(sent.map((message) => message.token)).toEqual(["device-ravi-join"]);
    expect(sent[0]?.data.kind).toBe("member_joined");
  });
});

describe("a dead registration", () => {
  it("is forgotten, so it is not retried forever", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-uninstalled");

    failWith = (token) => (token === "device-uninstalled" ? new Response(JSON.stringify({ error: { status: "NOT_FOUND" } }), { status: 404 }) : undefined) as Response | undefined;
    await arranged();

    ok(await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));
    await settled();

    const rows = await drizzle(env.DB).select().from(deviceTokens).all();
    expect(rows.map((row) => row.token)).not.toContain("device-uninstalled");
  });

  it("is not what a malformed payload looks like", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-still-good");

    failWith = () =>
      new Response(
        JSON.stringify({
          error: { status: "INVALID_ARGUMENT", details: [{ "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.data" }] }] },
        }),
        { status: 400 },
      );
    await arranged();

    ok(await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI));
    await settled();

    const rows = await drizzle(env.DB).select().from(deviceTokens).all();
    expect(rows.map((row) => row.token)).toContain("device-still-good");
  });
});

describe("with no Firebase configured", () => {
  it("records the expense and sends nothing", async () => {
    const fixture = await makeGroupOfTwo();
    await registerDevice(PRIYA, "device-unconfigured");

    const projectId = env.FCM_PROJECT_ID;
    env.FCM_PROJECT_ID = "";
    await arranged();

    // Push is the one feature this app is entirely usable without, and an
    // unconfigured deployment — a fork, a local run — is an ordinary state
    // rather than a failure.
    const written = await saveEntry(stub(fixture.groupId), evenly(freshId("e"), fixture.ravi.id, [fixture.ravi.id, fixture.priya.id], 40000), RAVI);
    await settled();
    env.FCM_PROJECT_ID = projectId;

    expect(written.ok).toBe(true);
    expect(sent).toEqual([]);
  });
});
