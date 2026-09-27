import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import type { IdentityOutcome } from "../src/schemas/identity";
import { googleIdToken } from "./google";
import { BY_INVITE, makeGroup, ok, RAVI, stub } from "./group";
import { signInAsGuest } from "./session";

/**
 * A guest signing in to an account they already had. Both are the same
 * person, so the guest's places go to that account rather than being left
 * behind as somebody who can never come back.
 */

async function continueWithGoogle(sub: string, email: string, token?: string): Promise<IdentityOutcome> {
  const response = await workerExports.default.fetch("https://opensplit.test/api/identity/google", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ idToken: await googleIdToken({ sub, email }), nonce: null, allowSignIn: true }),
  });
  expect(response.status).toBe(200);
  return (await response.json()) as IdentityOutcome;
}

/** Ravi's group, with a place the guest has claimed. */
async function groupWithGuest(guestId: string, placeName = "Priya") {
  const { groupId } = await makeGroup();
  const place = ok(await stub(groupId).putMember(`${groupId}-${placeName}`, { displayName: placeName, upiVpa: null, leftAt: null }, RAVI));
  const invite = ok(await stub(groupId).createInvite(place.id, RAVI));
  ok(await stub(groupId).join(invite.token, guestId, BY_INVITE));
  return { groupId, placeId: place.id };
}

async function memberRow(groupId: string, memberId: string) {
  return ok(await stub(groupId).changes(RAVI, 0, 500)).members.find((member) => member.id === memberId);
}

describe("a guest signing in to an account they already had", () => {
  it("brings their places along, and the account can read the group", async () => {
    const owner = await continueWithGoogle("handover-1", "handover-1@example.com");
    const guest = await signInAsGuest();
    const { groupId, placeId } = await groupWithGuest(guest.id);

    const outcome = await continueWithGoogle("handover-1", "handover-1@example.com", guest.token);
    expect(outcome).toMatchObject({ outcome: "replaced", strandedUserId: guest.id, account: { id: owner.account.id } });

    expect((await memberRow(groupId, placeId))?.profileId).toBe(owner.account.id);
    expect(ok(await stub(groupId).changes(owner.account.id, 0, 500)).groupId).toBe(groupId);

    const index = await env.DB.prepare("select profile_id from memberships where group_id = ?").bind(groupId).all<{ profile_id: string }>();
    expect(index.results.map((row) => row.profile_id).sort()).toEqual([RAVI, owner.account.id].sort());
  });

  it("ends the guest account, which nothing could reach again", async () => {
    await continueWithGoogle("handover-2", "handover-2@example.com");
    const guest = await signInAsGuest();
    await groupWithGuest(guest.id);

    await continueWithGoogle("handover-2", "handover-2@example.com", guest.token);

    expect(await env.DB.prepare("select id from user where id = ?").bind(guest.id).first()).toBeNull();
    const profile = await env.DB.prepare("select deleted_at from profiles where id = ?").bind(guest.id).first<{ deleted_at: string | null }>();
    expect(profile?.deleted_at).not.toBeNull();
  });

  /** Two places cannot become one row: the guest's stays, as a placeholder, with everything it paid and owes. */
  it("leaves the guest's place as a placeholder where the account is already a member", async () => {
    const owner = await continueWithGoogle("handover-3", "handover-3@example.com");
    const guest = await signInAsGuest();
    const { groupId, placeId } = await groupWithGuest(guest.id, "Guest Priya");

    const ownersPlace = ok(await stub(groupId).putMember(`${groupId}-owner`, { displayName: "Priya", upiVpa: null, leftAt: null }, RAVI));
    const invite = ok(await stub(groupId).createInvite(ownersPlace.id, RAVI));
    ok(await stub(groupId).join(invite.token, owner.account.id, BY_INVITE));

    await continueWithGoogle("handover-3", "handover-3@example.com", guest.token);

    expect((await memberRow(groupId, ownersPlace.id))?.profileId).toBe(owner.account.id);
    const left = await memberRow(groupId, placeId);
    expect(left?.profileId).toBeNull();
    expect(left?.displayName).toBe("Guest Priya");
  });

  it("does nothing when the guest simply attaches an identity", async () => {
    const guest = await signInAsGuest();
    const { groupId, placeId } = await groupWithGuest(guest.id);

    const outcome = await continueWithGoogle("handover-4", "handover-4@example.com", guest.token);
    expect(outcome).toMatchObject({ outcome: "kept", account: { id: guest.id } });
    expect((await memberRow(groupId, placeId))?.profileId).toBe(guest.id);
  });
});
