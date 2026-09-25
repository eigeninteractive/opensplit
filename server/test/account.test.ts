import { exports as workerExports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";

import type { ApiError } from "../src/schemas/common";
import type { AccountDeletion, Bootstrap, ChangePage, Joined, LinkPreview, MintedLink, Profile, ProfileList, ProfilePage } from "./api-types";
import { freshId } from "./group";
import { type Guest, signInAsGuest } from "./session";

/**
 * The person, rather than the ledger.
 *
 * Three things live here and they are connected by one rule: **who you can
 * see**. A profile is visible if you share a live membership with its owner,
 * plus your own. These are the tests that hold `visibleProfiles` to that,
 * because a visibility bug in a profile feed is somebody's payment handle
 * shown to a stranger.
 *
 * Account deletion is the other half. It is the one operation in this API that
 * destroys data, and the thing it must *not* destroy is everybody else's
 * ledger: money you paid is a fact about their group as much as yours.
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

async function makeGroup(host: Guest) {
  const id = freshId("acct");
  const created = await call("/api/groups", host, {
    method: "POST",
    body: JSON.stringify({ id, name: "Goa trip", defaultCurrency: "INR", memberId: `${id}-host`, displayName: "Ravi" }),
  });
  expect(created.status).toBe(200);
  return id;
}

/** Puts two accounts in one group, the only way the app can: a link, spent. */
async function share(host: Guest, guest: Guest, name: string) {
  const groupId = await makeGroup(host);
  const link = await json<MintedLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));

  const joined = await call(`/api/links/${link.token}/join`, guest, { method: "POST", body: JSON.stringify({ displayName: name }) });
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

    // Bank accounts close. A shape where this is inexpressible is a shape
    // where a stale handle keeps being offered as somewhere to send money —
    // which is what an optional field would have been, because the generated
    // client omits a null rather than sending one.
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
    const link = await json<MintedLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));
    for (const [index, friend] of friends.entries()) {
      await call(`/api/links/${link.token}/join`, friend, { method: "POST", body: JSON.stringify({ displayName: `Friend ${index}` }) });
      await named(friend, `Friend ${index}`);
    }

    const collected: string[] = [];
    let cursor: ProfilePage = { profiles: [], cursor: null, cursorId: null, hasMore: true };
    let pages = 0;

    while (cursor.hasMore && pages < 10) {
      const query = cursor.cursor ? `?limit=2&since=${encodeURIComponent(cursor.cursor)}&sinceId=${cursor.cursorId}` : "?limit=2";
      cursor = await json<ProfilePage>(await call(`/api/profiles${query}`, host));
      collected.push(...cursor.profiles.map((row) => row.id));
      pages += 1;
    }

    expect(cursor.hasMore).toBe(false);
    expect(new Set(collected)).toEqual(new Set([host.id, ...friends.map((friend) => friend.id)]));

    // No row twice. A cursor on the timestamp alone would either repeat the
    // boundary row forever or skip past it, and which of the two you got would
    // depend on how many profiles happened to share a millisecond.
    expect(collected.length).toBe(new Set(collected).size);
  });

  it("does not surface a profile you were never meant to see, even by name", async () => {
    const stranger = await signInAsGuest();
    await named(stranger, "Zara");

    const { profiles } = await json<ProfileList>(await call(`/api/profiles/by-ids?ids=${stranger.id},${ravi.id}`, ravi));

    // Present but empty rather than refused: the caller is asking about ids it
    // holds for its own reasons, and "you cannot see that" and "that does not
    // exist" are deliberately the same answer.
    expect(profiles.map((row) => row.id)).toEqual([ravi.id]);
  });

  it("answers for somebody who only just became visible", async () => {
    const host = await signInAsGuest();
    const friend = await signInAsGuest();

    // Named long before they meet, which is the case the feed cannot serve: by
    // the time the membership exists, the host's cursor is already past this
    // row and no incremental pull will ever mention it again.
    await named(friend, "Priya");
    await named(host, "Ravi");

    const swept = await json<ProfilePage>(await call("/api/profiles", host));
    expect(swept.profiles.map((row) => row.id)).not.toContain(friend.id);

    await share(host, friend, "Priya");

    const { profiles } = await json<ProfileList>(await call(`/api/profiles/by-ids?ids=${friend.id}`, host));
    expect(profiles).toEqual([expect.objectContaining({ id: friend.id, displayName: "Priya" })]);
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

    // A phone that changes hands keeps its registration token, so the claim
    // has to transfer rather than be refused — otherwise the previous owner's
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

  it("collects a group nobody left could ever read", async () => {
    const solo = await signInAsGuest();
    const groupId = await makeGroup(solo);

    const deleted = await json<AccountDeletion>(await call("/api/account", solo, { method: "DELETE" }));
    expect(deleted).toEqual({ forgotten: 1, purged: 1 });

    // Holding somebody's expense descriptions forever in a group with no
    // living reader is the opposite of what deleting an account asks for.
    //
    // What is left is a tombstone, and it answers anybody — there is no
    // membership left to check and nothing to protect, and refusing would
    // leave every device that still holds a copy holding it forever.
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
    await share(friend, going, "Zara");

    expect((await call("/api/account", going, { method: "DELETE" })).status).toBe(200);

    // The session is gone with the account, so the device is signed out by
    // consequence rather than by a second call.
    expect((await call("/api/bootstrap", going)).status).toBe(401);

    // The row survives as a tombstone — the id must never be handed to a new
    // account — but with nothing left in it. A UPI address belonging to an
    // account that no longer exists is money sent nowhere.
    const { profiles } = await json<ProfileList>(await call(`/api/profiles/by-ids?ids=${going.id}`, friend));
    expect(profiles).toEqual([]);
  });

  it("is refused without a session", async () => {
    expect((await call("/api/account", null, { method: "DELETE" })).status).toBe(401);
  });
});

describe("a guest who never became anybody", () => {
  it("still gets a profile, a bootstrap and an empty feed", async () => {
    const guest = await signInAsGuest();
    const body = await json<Bootstrap>(await call("/api/bootstrap", guest));

    expect(body).toEqual({ profileId: guest.id, displayName: null, upiVpa: null, isAnonymous: true, groupIds: [] });

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

    const link = await json<MintedLink>(await call(`/api/groups/${groupId}/link`, host, { method: "POST" }));
    const preview = await json<LinkPreview>(await call(`/api/links/${link.token}`, friend));

    expect(preview.isMember).toBe(true);
    expect(preview.memberCount).toBe(2);
  });
});
