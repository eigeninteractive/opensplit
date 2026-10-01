import { exports as workerExports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";

import type { ApiError } from "../src/schemas/common";
import type { AccountDeletion, ChangePage, GroupIds, GroupLink, Joined, LinkPreview, Profile, ProfilePage } from "./api-types";
import { freshId } from "./group";
import { type Guest, signInAsGuest } from "./session";

/** The person, rather than the ledger. */

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

async function makeGroup(host: Guest) {
  const id = freshId("acct");
  const created = await call(`/api/groups/${id}`, host, {
    method: "PUT",
    body: JSON.stringify({ name: "Goa trip", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, archivedAt: null, creatorId: `${id}-host`, creatorName: "Ravi" }),
  });
  expect(created.status).toBe(200);
  return id;
}

/** Puts two accounts in one group, the only way the app can: a link, spent. */
async function share(host: Guest, guest: Guest, name: string) {
  const groupId = await makeGroup(host);
  const link = await json<GroupLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));

  const joined = await call(`/api/links/${link.token}/join`, guest, { method: "POST", body: JSON.stringify({ memberId: null, displayName: name }) });
  expect(joined.status).toBe(200);

  return { groupId, member: (await json<Joined>(joined)).member };
}

async function writeProfile(guest: Guest, displayName: string | null, upiVpa: string | null = null): Promise<Profile> {
  const response = await call("/api/profile", guest, { method: "PUT", body: JSON.stringify({ displayName, upiVpa }) });
  expect(response.status).toBe(200);
  return json<Profile>(response);
}

const named = (guest: Guest, displayName: string) => writeProfile(guest, displayName);

let ravi: Guest;

beforeAll(async () => {
  ravi = await signInAsGuest();
});

describe("your own profile", () => {
  it("is the only one the endpoint can write", async () => {
    const me = await signInAsGuest();

    // A guest has no name of its own, and that null is load-bearing: claiming
    // an invite adopts the name a friend typed only when there is none here.
    const before = await json<ProfilePage>(await call("/api/profiles", me));
    expect(before.profiles).toEqual([expect.objectContaining({ id: me.id, displayName: null, upiVpa: null, deletedAt: null })]);

    const written = await named(me, "Ravi");
    expect(written.id).toBe(me.id);
    expect(written.displayName).toBe("Ravi");

    // There is no field to point at anybody else, which is the whole design:
    // nothing has to check that you are not writing a stranger's payment
    // handle, because the request cannot name one.
    const handled = await writeProfile(me, "Ravi", "ravi@okhdfcbank");
    expect(handled.displayName).toBe("Ravi");
    expect(handled.upiVpa).toBe("ravi@okhdfcbank");
  });

  it("can clear a payment handle, not only add one", async () => {
    const me = await signInAsGuest();
    await writeProfile(me, "Priya", "priya@oksbi");

    // Bank accounts close.
    const cleared = await writeProfile(me, "Priya S", null);
    expect(cleared.upiVpa).toBeNull();
    expect(cleared.displayName).toBe("Priya S");
  });

  it("refuses a payment handle that is not one", async () => {
    const refused = await call("/api/profile", ravi, { method: "PUT", body: JSON.stringify({ displayName: "Ravi", upiVpa: "not a vpa" }) });
    expect(refused.status).toBe(400);
    expect((await json<ApiError>(refused)).error.code).toBe("malformed");
  });

  it("requires both fields, so neither can be silently left behind", async () => {
    const refused = await call("/api/profile", ravi, { method: "PUT", body: JSON.stringify({ displayName: "Ravi" }) });
    expect(refused.status).toBe(400);
  });
});

describe("the profile feed", () => {
  it("carries people you share a group with, and nobody else", async () => {
    const host = await signInAsGuest();
    const friend = await signInAsGuest();
    const stranger = await signInAsGuest();

    await named(host, "Ravi");
    await named(friend, "Priya");
    await named(stranger, "Zara");

    await share(host, friend, "Priya");

    const seen = await json<ProfilePage>(await call("/api/profiles", host));
    const ids = seen.profiles.map((row) => row.id);

    expect(ids).toContain(host.id);
    expect(ids).toContain(friend.id);
    expect(ids).not.toContain(stranger.id);

    // Symmetric, which is what makes a settle-up possible: Priya needs Ravi's
    // payment handle exactly as much as Ravi needs hers.
    const other = await json<ProfilePage>(await call("/api/profiles", friend));
    expect(other.profiles.map((row) => row.id)).toContain(host.id);
  });

  it("pages on the pair, so two renames in one millisecond cannot hide one", async () => {
    const host = await signInAsGuest();
    const friends = [await signInAsGuest(), await signInAsGuest(), await signInAsGuest()];

    const groupId = await makeGroup(host);
    const link = await json<GroupLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));
    for (const [index, friend] of friends.entries()) {
      await call(`/api/links/${link.token}/join`, friend, { method: "POST", body: JSON.stringify({ memberId: null, displayName: `Friend ${index}` }) });
      await named(friend, `Friend ${index}`);
    }

    const collected: string[] = [];
    let cursor: ProfilePage = { profiles: [], cursor: null, hasMore: true };
    let pages = 0;

    while (cursor.hasMore && pages < 10) {
      const query = cursor.cursor ? `?limit=2&after=${encodeURIComponent(cursor.cursor)}` : "?limit=2";
      cursor = await json<ProfilePage>(await call(`/api/profiles${query}`, host));
      collected.push(...cursor.profiles.map((row) => row.id));
      pages += 1;
    }

    expect(cursor.hasMore).toBe(false);
    expect(new Set(collected)).toEqual(new Set([host.id, ...friends.map((friend) => friend.id)]));

    // No row twice.
    expect(collected.length).toBe(new Set(collected).size);
  });
});

describe("a group's change page", () => {
  it("carries the profiles of the group's members, and nobody else's", async () => {
    const host = await signInAsGuest();
    const friend = await signInAsGuest();
    const stranger = await signInAsGuest();
    await named(stranger, "Zara");
    const { groupId } = await share(host, friend, "Priya");

    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, host));
    expect(page.profiles.map((row) => row.id).sort()).toEqual([host.id, friend.id].sort());
  });

  // 121 accounts joining one at a time, each through the group's object and on
  // to D1: half a second on a laptop, four or five on a CI runner, which is the
  // default limit. The size is the point of the test, so the limit gives way.
  it("carries more profiles than D1 binds in one query", async () => {
    const host = await signInAsGuest();
    const groupId = await makeGroup(host);
    const link = await json<GroupLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));
    const arrivals = await Promise.all(Array.from({ length: 120 }, () => signInAsGuest()));
    for (const [index, guest] of arrivals.entries()) {
      await call(`/api/links/${link.token}/join`, guest, { method: "POST", body: JSON.stringify({ memberId: null, displayName: `Friend ${index}` }) });
    }

    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, host));
    expect(page.profiles).toHaveLength(121);
  }, 30_000);

  it("carries somebody who only just became visible, though the profile feed has passed them", async () => {
    const host = await signInAsGuest();
    const friend = await signInAsGuest();

    // Named long before they meet, which is the case the feed cannot serve: by
    // the time the membership exists, the host's cursor is already past this
    // row and no incremental pull will ever mention it again.
    await named(friend, "Priya");
    await named(host, "Ravi");

    const swept = await json<ProfilePage>(await call("/api/profiles", host));
    expect(swept.profiles.map((row) => row.id)).not.toContain(friend.id);

    const { groupId } = await share(host, friend, "Priya");

    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, host));
    expect(page.profiles).toContainEqual(expect.objectContaining({ id: friend.id, displayName: "Priya" }));
  });
});

describe("devices", () => {
  it("registers, transfers and forgets a token", async () => {
    const first = await signInAsGuest();
    const second = await signInAsGuest();
    const token = `fcm-${freshId("dev")}`;

    expect((await call("/api/devices", first, { method: "PUT", body: JSON.stringify({ token, platform: "android" }) })).status).toBe(200);

    // Idempotent: a token is re-registered on every launch.
    expect((await call("/api/devices", first, { method: "PUT", body: JSON.stringify({ token, platform: "android" }) })).status).toBe(200);

    // A phone that changes hands keeps its registration token, so the claim has
    // to transfer rather than be refused — otherwise the previous owner's
    // notifications follow the new one.
    expect((await call("/api/devices", second, { method: "PUT", body: JSON.stringify({ token, platform: "android" }) })).status).toBe(200);

    // Which means the previous owner can no longer forget it.
    expect(await json<{ forgotten: boolean }>(await call(`/api/devices/${encodeURIComponent(token)}`, first, { method: "DELETE" }))).toEqual({ forgotten: false });
    expect(await json<{ forgotten: boolean }>(await call(`/api/devices/${encodeURIComponent(token)}`, second, { method: "DELETE" }))).toEqual({ forgotten: true });
  });

  it("is refused without a session", async () => {
    expect((await call("/api/devices", null, { method: "PUT", body: JSON.stringify({ token: "x", platform: "web" }) })).status).toBe(401);
  });
});

describe("deleting an account", () => {
  it("leaves a shared group intact and gives the place back", async () => {
    const leaving = await signInAsGuest();
    const staying = await signInAsGuest();
    await named(leaving, "Ravi");

    const { groupId, member } = await share(staying, leaving, "Ravi");

    const deleted = await json<AccountDeletion>(await call("/api/account", leaving, { method: "DELETE" }));
    expect(deleted).toEqual({ forgotten: 1, purged: 0 });

    // The group is untouched for everybody else, and the member row keeps its
    // name: money Ravi paid is a fact about Priya's group as much as his.
    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, staying));
    const row = page.members.find((each) => each.id === member.id);
    expect(row?.displayName).toBe("Ravi");

    // And loses its account, which is exactly the state of somebody a friend
    // added who never signed up.
    expect(row?.profileId).toBeNull();
  });

  it("leaves the place under the name the account last had, not the one it joined with", async () => {
    const leaving = await signInAsGuest();
    const staying = await signInAsGuest();
    const { groupId, member } = await share(staying, leaving, "Ravi");
    await named(leaving, "Ravi Kumar");

    await call("/api/account", leaving, { method: "DELETE" });

    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, staying));
    expect(page.members.find((each) => each.id === member.id)?.displayName).toBe("Ravi Kumar");
  });

  it("collects a group nobody left could ever read", async () => {
    const solo = await signInAsGuest();
    const groupId = await makeGroup(solo);

    const deleted = await json<AccountDeletion>(await call("/api/account", solo, { method: "DELETE" }));
    expect(deleted).toEqual({ forgotten: 1, purged: 1 });

    // Holding somebody's expense descriptions forever in a group with no living
    // reader is the opposite of what deleting an account asks for.
    const after = await signInAsGuest();
    const grave = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, after));

    expect(grave.purgedAt).not.toBeNull();
    expect(grave.members).toEqual([]);
    expect(grave.entries).toEqual([]);
    expect(grave.group).toBeNull();
  });

  it("takes the session, the profile's contents and the push registrations with it", async () => {
    const going = await signInAsGuest();
    await writeProfile(going, "Zara", "zara@okaxis");

    const token = `fcm-${freshId("gone")}`;
    await call("/api/devices", going, { method: "PUT", body: JSON.stringify({ token, platform: "android" }) });

    // A group with somebody else in it, so the account survives long enough
    // for its own profile to be checked from the other side.
    const friend = await signInAsGuest();
    await named(friend, "Priya");
    const { groupId } = await share(friend, going, "Zara");

    expect((await call("/api/account", going, { method: "DELETE" })).status).toBe(200);

    // The session is gone with the account, so the device is signed out by
    // consequence rather than by a second call.
    expect((await call("/api/groups", going)).status).toBe(401);

    // The place is a placeholder now, so the group no longer names the account at all.
    const page = await json<ChangePage>(await call(`/api/groups/${groupId}/changes?since=0`, friend));
    expect(page.profiles.map((row) => row.id)).not.toContain(going.id);
  });

  it("is refused without a session", async () => {
    expect((await call("/api/account", null, { method: "DELETE" })).status).toBe(401);
  });
});

describe("a guest who never became anybody", () => {
  it("still gets a profile, no groups and an empty feed", async () => {
    const guest = await signInAsGuest();
    expect(await json<GroupIds>(await call("/api/groups", guest))).toEqual({ groupIds: [] });

    // Visible only to themselves, which is the degenerate case of the rule
    // rather than a special one: nobody shares a group with them yet.
    const page = await json<ProfilePage>(await call("/api/profiles", guest));
    expect(page.profiles.map((row) => row.id)).toEqual([guest.id]);
  });
});

describe("a link preview", () => {
  it("reports the caller's own membership once they have joined", async () => {
    const host = await signInAsGuest();
    const friend = await signInAsGuest();
    const { groupId } = await share(host, friend, "Priya");

    const link = await json<GroupLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));
    const preview = await json<LinkPreview>(await call(`/api/links/${link.token}`, friend));

    expect(preview.isMember).toBe(true);
    expect(preview.memberCount).toBe(2);
  });
});
