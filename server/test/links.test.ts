import { exports as workerExports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";

import type { ApiError } from "../src/schemas/common";
import type { GroupLink, Invite, Joined, LinkPreview, LinkRevocation, LiveLink, PlaceholderList, ProfileList } from "./api-types";
import { freshId } from "./group";
import { type Guest, signInAsGuest } from "./session";

/**
 * Arriving, over HTTP.
 *
 * `invites.test.ts` already holds the rules — who may mint, what a spent token
 * does, that claiming a place moves no money. This suite is about the layer on
 * top of them, and specifically about the one thing that layer has to do and
 * the Durable Object cannot: turn a token somebody tapped into the group whose
 * object knows what it means. Everything here goes through `link_tokens` in D1,
 * which is written by the object's outbox rather than by the request, so a
 * route that never flushed would fail here and nowhere else.
 *
 * The other half is the ordering. Previewing a link with no session at all is
 * not a convenience — it is the fix for the bug that stranded people outside
 * their own groups — so it is asserted as a property of the route rather than
 * left to the client to use correctly.
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

/** A group with the caller in it and one placeholder waiting to be claimed. */
async function makeGroup(host: Guest, placeholder = "Priya") {
  const id = freshId("link");
  const memberId = `${id}-host`;

  const created = await call("/api/groups", host, {
    method: "POST",
    body: JSON.stringify({ id, name: "Goa trip", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, memberId, displayName: "Ravi" }),
  });
  expect(created.status).toBe(200);

  const slotId = `${id}-slot`;
  const slot = await call(`/api/groups/${id}/members`, host, {
    method: "POST",
    body: JSON.stringify({ id: slotId, displayName: placeholder, upiVpa: null }),
  });
  expect(slot.status).toBe(200);

  return { id, memberId, slotId };
}

let ravi: Guest;
let priya: Guest;

beforeAll(async () => {
  ravi = await signInAsGuest();
  priya = await signInAsGuest();
});

describe("an invite", () => {
  it("is previewable by somebody with no session, and then spendable", async () => {
    const { id, slotId } = await makeGroup(ravi);

    const minted = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));
    expect(minted.memberId).toBe(slotId);

    // No session. This is the whole ordering fix: somebody who already has an
    // account sees what they were sent before anything claims the slot on
    // their behalf.
    const preview = await call(`/api/links/${minted.token}`, null);
    expect(preview.status).toBe(200);

    const seen = await json<LinkPreview>(preview);
    expect(seen).toMatchObject({
      kind: "invite",
      groupId: id,
      groupName: "Goa trip",
      memberName: "Priya",
      inviterName: "Ravi",
      isRedeemed: false,
      isExpired: false,
      isRevoked: false,
      // False with no session, rather than unknown. A screen that cannot tell
      // "you are already in this group" from "we did not ask" offers a Join
      // button that is going to be refused.
      isMember: false,
    });

    const joined = await json<Joined>(await call(`/api/links/${minted.token}/join`, priya, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) }));
    expect(joined.member.id).toBe(slotId);
    expect(joined.member.profileId).toBe(priya.id);

    // The place was claimed, not duplicated: one column changed on a row that
    // already existed, which is the entire payoff of members being
    // group-scoped rather than accounts.
    expect(joined.member.displayName).toBe("Priya");
  });

  it("says it is spent rather than saying nothing", async () => {
    const { id, slotId } = await makeGroup(ravi);
    const minted = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));

    expect((await call(`/api/links/${minted.token}/join`, priya, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) })).status).toBe(200);

    const again = await signInAsGuest();
    const refused = await call(`/api/links/${minted.token}/join`, again, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) });
    expect(refused.status).toBe(409);
    expect((await json<ApiError>(refused)).error.code).toBe("invite_spent");

    // And the preview still describes it, so the screen can say which of the
    // three reasons it is rather than "invalid link".
    const preview = await json<LinkPreview>(await call(`/api/links/${minted.token}`, null));
    expect(preview.isRedeemed).toBe(true);
  });

  it("stops routing once a newer one replaces it", async () => {
    const { id, slotId } = await makeGroup(ravi);

    const first = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));
    const second = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));

    // The index has to forget it, or a URL sitting in a chat history still
    // resolves to a group even though the object would refuse to spend it.
    const stale = await call(`/api/links/${first.token}`, null);
    expect(stale.status).toBe(404);

    expect((await call(`/api/links/${second.token}`, null)).status).toBe(200);
  });
});

describe("an open link", () => {
  it("is mintable, readable, and revocable by a member", async () => {
    const { id } = await makeGroup(ravi);

    expect((await json<LiveLink>(await call(`/api/groups/${id}/link`, ravi))).link).toBeNull();

    const minted = await json<GroupLink>(await call(`/api/groups/${id}/link`, ravi, { method: "POST" }));

    const live = await json<LiveLink>(await call(`/api/groups/${id}/link`, ravi));
    expect(live.link?.token).toBe(minted.token);

    const revoked = await json<LinkRevocation>(await call(`/api/groups/${id}/link`, ravi, { method: "DELETE" }));
    expect(revoked.revoked).toBe(minted.token);

    expect((await json<LiveLink>(await call(`/api/groups/${id}/link`, ravi))).link).toBeNull();

    // Still describes itself, and says which kind of no this is.
    const preview = await json<LinkPreview>(await call(`/api/links/${minted.token}`, null));
    expect(preview.isRevoked).toBe(true);
  });

  it("is not a way for a stranger to get one", async () => {
    const { id } = await makeGroup(ravi);

    // The difference between reading a link and being handed one. A preview
    // answers whoever holds the URL; this hands a working URL out, so anybody
    // who could call it could invite the world in.
    for (const method of ["GET", "POST", "DELETE"]) {
      const refused = await call(`/api/groups/${id}/link`, priya, { method });
      expect(refused.status, method).toBe(403);
      expect((await json<ApiError>(refused)).error.code).toBe("not_member");
    }
  });

  it("offers the places already typed in, to somebody who has signed in", async () => {
    const { id, slotId } = await makeGroup(ravi);
    const minted = await json<GroupLink>(await call(`/api/groups/${id}/link`, ravi, { method: "POST" }));

    // Names are more than the link implies to whoever holds it, so this one
    // needs a session where the preview does not.
    const anonymous = await call(`/api/links/${minted.token}/placeholders`, null);
    expect(anonymous.status).toBe(401);

    const { placeholders } = await json<PlaceholderList>(await call(`/api/links/${minted.token}/placeholders`, priya));
    expect(placeholders).toEqual([{ memberId: slotId, displayName: "Priya" }]);

    // Claiming one is what stops a group of six becoming a group of twelve
    // when one link is pasted into a chat.
    const joined = await json<Joined>(await call(`/api/links/${minted.token}/join`, priya, { method: "POST", body: JSON.stringify({ memberId: slotId, displayName: null }) }));
    expect(joined.member.id).toBe(slotId);

    const after = await json<PlaceholderList>(await call(`/api/links/${minted.token}/placeholders`, ravi));
    expect(after.placeholders).toEqual([]);
  });

  it("lets somebody nobody typed in arrive under their own name", async () => {
    const { id } = await makeGroup(ravi);
    const minted = await json<GroupLink>(await call(`/api/groups/${id}/link`, ravi, { method: "POST" }));

    const zara = await signInAsGuest();
    const joined = await json<Joined>(await call(`/api/links/${minted.token}/join`, zara, { method: "POST", body: JSON.stringify({ memberId: null, displayName: "Zara" }) }));

    expect(joined.member.displayName).toBe("Zara");
    expect(joined.member.profileId).toBe(zara.id);

    // A name is the one thing this branch cannot do without, and the refusal
    // is the object's rather than the schema's: `displayName` is legitimately
    // null when a placeholder is being claimed instead.
    //
    // No sentinel. "Someone" in a ledger is worse than being asked, and a
    // sentinel in the profile could never be told from a name somebody meant.
    const nameless = await signInAsGuest();
    const refused = await call(`/api/links/${minted.token}/join`, nameless, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) });
    expect(refused.status).toBe(400);
    expect((await json<ApiError>(refused)).error.code).toBe("malformed");
  });

  it("uses the name already on the account when none is typed", async () => {
    const { id } = await makeGroup(ravi);
    const minted = await json<GroupLink>(await call(`/api/groups/${id}/link`, ravi, { method: "POST" }));

    // Anybody who signed in with Google or an email address has one, which is
    // most people arriving on a link.
    const known = await signInAsGuest();
    await call("/api/profile", known, { method: "PUT", body: JSON.stringify({ displayName: "Zara", upiVpa: null }) });

    const joined = await json<Joined>(await call(`/api/links/${minted.token}/join`, known, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) }));
    expect(joined.member.displayName).toBe("Zara");
  });
});

describe("the name, travelling the other way", () => {
  it("is adopted from the place a friend typed, when the account has none", async () => {
    const { id, slotId } = await makeGroup(ravi, "Priya");
    const minted = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));

    const arriving = await signInAsGuest();
    await call(`/api/links/${minted.token}/join`, arriving, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) });

    // Somebody arriving on an invite signed in as a guest a moment earlier and
    // has no name at all, while the group already knows them as whatever was
    // typed on the placeholder. A group's object holds member names and D1
    // holds the account's; the join route is the only place the two meet.
    const { profiles } = await json<ProfileList>(await call(`/api/profiles/by-ids?ids=${arriving.id}`, ravi));
    expect(profiles).toEqual([expect.objectContaining({ id: arriving.id, displayName: "Priya" })]);
  });

  it("never overwrites a name somebody chose with a friend's guess", async () => {
    const { id, slotId } = await makeGroup(ravi, "P");
    const minted = await json<Invite>(await call(`/api/groups/${id}/members/${slotId}/invite`, ravi, { method: "POST" }));

    const arriving = await signInAsGuest();
    await call("/api/profile", arriving, { method: "PUT", body: JSON.stringify({ displayName: "Priya Sharma", upiVpa: null }) });
    const claimed = await json<Joined>(await call(`/api/links/${minted.token}/join`, arriving, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) }));

    // The slot keeps the name the group knows, and the account keeps its own.
    // That "only if it has none" is the entire check, and it is why a guest's
    // profile carries a null rather than the anonymous plugin's invention.
    expect(claimed.member.displayName).toBe("P");

    const { profiles } = await json<ProfileList>(await call(`/api/profiles/by-ids?ids=${arriving.id}`, ravi));
    expect(profiles[0]?.displayName).toBe("Priya Sharma");
  });

  it("tells somebody already inside that they are, rather than offering to let them in", async () => {
    const { id } = await makeGroup(ravi);
    const minted = await json<GroupLink>(await call(`/api/groups/${id}/link`, ravi, { method: "POST" }));

    const preview = await json<LinkPreview>(await call(`/api/links/${minted.token}`, ravi));
    expect(preview.isMember).toBe(true);

    const refused = await call(`/api/links/${minted.token}/join`, ravi, { method: "POST", body: JSON.stringify({ memberId: null, displayName: "Ravi again" }) });
    expect(refused.status).toBe(409);
    expect((await json<ApiError>(refused)).error.code).toBe("already_member");
  });
});

describe("a token that names nothing", () => {
  it("is a 404 on every route that takes one", async () => {
    const unknown = freshId("nope");

    expect((await call(`/api/links/${unknown}`, null)).status).toBe(404);
    expect((await call(`/api/links/${unknown}/placeholders`, priya)).status).toBe(404);
    expect((await call(`/api/links/${unknown}/join`, priya, { method: "POST", body: JSON.stringify({ memberId: null, displayName: null }) })).status).toBe(404);

    // The same answer a wrong token gets, deliberately: telling the two apart
    // turns the endpoint into an oracle for which tokens exist.
    expect((await json<ApiError>(await call(`/api/links/${unknown}`, null))).error.code).toBe("invite_invalid");
  });
});
