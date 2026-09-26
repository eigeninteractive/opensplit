import { describe, expect, it } from "vitest";

import { BY_INVITE, evenly, freshId, makeGroup, ok, PRIYA, refusal, stub, sumOf, ZARA } from "./group";

/** Invites, links, and what a stranger can reach: a token spent exactly once, an expired one, a revoked one, and a group nobody outside it can read. */

describe("a stranger holding no token", () => {
  it("sees nothing of a group they are not in, whatever they ask for", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1200), ravi.profileId ?? ""));

    // One refusal, four ways in. Nothing here can answer a stranger with an
    // empty result that reads as "nothing to see" rather than "not for you".
    expect(refusal(await stub(groupId).changes(ZARA, 0, 100)).code).toBe("not_member");
    expect(refusal(await stub(groupId).createInvite(priya.id, ZARA)).code).toBe("not_member");
    expect(refusal(await stub(groupId).createLink(ZARA)).code).toBe("not_member");
    expect(refusal(await stub(groupId).update({ name: "Zara's now", simplifyDebts: true, archivedAt: null }, ZARA)).code).toBe("not_member");
  });
});

describe("an invite to one named place", () => {
  it("can be issued for an unclaimed place, and describes itself to whoever holds it", async () => {
    const { groupId, priya, ravi } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(priya.id, ravi.profileId ?? ""));

    // No session: the person who just tapped the link has not been asked who
    // they are yet, and asking before showing them what they are being asked
    // about is how people join as the wrong account.
    const preview = ok(await stub(groupId).peekLink(invite.token, null));
    expect(preview).toMatchObject({
      kind: "invite",
      groupName: "Goa trip",
      memberName: "Priya",
      inviterName: "Ravi",
      isRedeemed: false,
      isExpired: false,
      isMember: false,
    });
  });

  it("cannot be issued for a place somebody already holds — that is a takeover", async () => {
    const { groupId, ravi } = await makeGroup();
    expect(refusal(await stub(groupId).createInvite(ravi.id, ravi.profileId ?? "")).code).toBe("slot_taken");
  });

  it("is claimed by setting exactly one column, so no balance moves", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    ok(await object.upsertEntry(evenly(freshId("e"), priya.id, [ravi.id, priya.id], 1000), profile));
    const before = ok(await object.changes(profile, 0, 500));
    const entriesBefore = before.entries.map((entry) => ({ id: entry.id, payers: entry.payers, shares: entry.shares }));

    const invite = ok(await object.createInvite(priya.id, profile));
    const claimed = ok(await object.join(invite.token, PRIYA, BY_INVITE)).member;

    expect(claimed.id).toBe(priya.id);
    expect(claimed.profileId).toBe(PRIYA);
    expect(claimed.displayName).toBe("Priya");
    expect(claimed.joinedAt).toBe(priya.joinedAt);

    const after = ok(await object.changes(profile, 0, 500));
    expect(after.entries.map((entry) => ({ id: entry.id, payers: entry.payers, shares: entry.shares }))).toEqual(entriesBefore);
  });

  it("is spent exactly once", async () => {
    const { groupId, priya, ravi } = await makeGroup();
    const object = stub(groupId);
    const invite = ok(await object.createInvite(priya.id, ravi.profileId ?? ""));

    ok(await object.join(invite.token, PRIYA, BY_INVITE));
    expect(refusal(await object.join(invite.token, ZARA, BY_INVITE)).code).toBe("invite_spent");
  });

  it("is refused when the token names nothing", async () => {
    const { groupId } = await makeGroup();
    expect(refusal(await stub(groupId).join(freshId("t"), PRIYA, BY_INVITE)).code).toBe("invite_invalid");
    expect(ok(await stub(groupId).peekLink(freshId("t"), null))).toBeNull();
  });

  it("is invalidated by reissuing, so a link left in a chat cannot still be spent", async () => {
    const { groupId, priya, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const first = ok(await object.createInvite(priya.id, profile));
    const second = ok(await object.createInvite(priya.id, profile));

    expect(refusal(await object.join(first.token, PRIYA, BY_INVITE)).code).toBe("invite_invalid");
    expect(ok(await object.join(second.token, PRIYA, BY_INVITE)).member.id).toBe(priya.id);
  });

  it("cannot give one account a second place in the same group", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const invite = ok(await object.createInvite(priya.id, ravi.profileId ?? ""));

    expect(refusal(await object.join(invite.token, ravi.profileId ?? "", BY_INVITE)).code).toBe("already_member");
  });

  it("expires, so a link forwarded into a chat does not live forever", async () => {
    const { groupId, priya, ravi } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(priya.id, ravi.profileId ?? ""));

    const days = (Date.parse(invite.expiresAt) - Date.parse(invite.createdAt)) / 86_400_000;
    expect(days).toBeLessThanOrEqual(30);
  });
});

describe("the group's one open link", () => {
  it("lets somebody nobody invited personally walk in, and says so on the record", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const link = ok(await object.createLink(profile));
    const joined = ok(await object.join(link.token, ZARA, { memberId: null, displayName: "Zara" })).member;

    expect(joined.profileId).toBe(ZARA);
    expect(joined.displayName).toBe("Zara");

    const page = ok(await object.changes(profile, 0, 500));
    expect(page.events.map((event) => event.kind)).toContain("link_created");
    expect(page.events.map((event) => event.kind)).toContain("member_joined");
  });

  it("leaves exactly one live link when minted twice, not two open doors", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const first = ok(await object.createLink(profile));
    const second = ok(await object.createLink(profile));

    expect(refusal(await object.join(first.token, ZARA, { memberId: null, displayName: "Zara" })).code).toBe("invite_invalid");
    expect(ok(await object.join(second.token, ZARA, { memberId: null, displayName: "Zara" })).member.displayName).toBe("Zara");

    /**
     * A rotation is one change that says two things, so both lines share a
     * sequence number and a timestamp. `ordinal` is the only thing that keeps
     * them from rendering as a link created and then immediately revoked, which
     * reads as the opposite of what happened.
     */
    const page = ok(await object.changes(profile, 0, 500));
    const rotation = page.events.filter((event) => event.kind === "link_revoked" || event.kind === "link_created");
    const together = rotation.filter((event) => event.seq === rotation.at(-1)?.seq);
    expect(together.map((event) => event.ordinal)).toEqual([0, 1]);
    expect(together.map((event) => event.kind)).toEqual(["link_revoked", "link_created"]);
  });

  it("can be turned off outright, and the closing is on the record too", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const link = ok(await object.createLink(profile));
    expect(ok(await object.revokeLink(profile)).revoked).toBe(link.token);

    expect(refusal(await object.join(link.token, ZARA, { memberId: null, displayName: "Zara" })).code).toBe("invite_spent");

    const page = ok(await object.changes(profile, 0, 500));
    const kinds = page.events.map((event) => event.kind);
    expect(kinds.filter((kind) => kind === "link_revoked")).toHaveLength(1);
  });

  /**
   * The case this exists for: Priya makes the group and types in everybody on
   * the trip, then posts one link. Without it, each arrival becomes a new
   * member beside the placeholder that is already them.
   */
  it("offers the places going spare, and only the places going spare", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const link = ok(await object.createLink(profile));
    const spare = ok(await object.placeholders(link.token)).placeholders;

    expect(spare.map((row) => row.displayName)).toEqual(["Priya"]);
    expect(spare.map((row) => row.id)).not.toContain(ravi.id);

    const claimed = ok(await object.join(link.token, PRIYA, { memberId: priya.id, displayName: null })).member;
    expect(claimed.id).toBe(priya.id);
    expect(ok(await object.placeholders(link.token)).placeholders).toHaveLength(0);
  });

  it("does not offer a member list to somebody holding a revoked token", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const link = ok(await object.createLink(profile));
    ok(await object.revokeLink(profile));

    expect(refusal(await object.placeholders(link.token)).code).toBe("invite_spent");
  });

  it("refuses a second claim on a place taken between the peek and the join", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const link = ok(await object.createLink(ravi.profileId ?? ""));

    ok(await object.join(link.token, PRIYA, { memberId: priya.id, displayName: null }));
    expect(refusal(await object.join(link.token, ZARA, { memberId: priya.id, displayName: null })).code).toBe("slot_taken");
  });

  it("tells somebody who is already in the group that they are", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const link = ok(await object.createLink(profile));
    expect(ok(await object.peekLink(link.token, profile))?.isMember).toBe(true);
    expect(ok(await object.peekLink(link.token, ZARA))?.isMember).toBe(false);
  });
});

describe("what joining does to the ledger", () => {
  it("does nothing to it at all — which is the whole reason members are group-scoped", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const entry = ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1500), profile));
    const invite = ok(await object.createInvite(priya.id, profile));
    ok(await object.join(invite.token, PRIYA, BY_INVITE));

    const page = ok(await object.changes(profile, 0, 500));
    const after = page.entries.find((row) => row.id === entry.id);

    expect(after?.seq).toBe(entry.seq);
    expect(after?.createdBy).toBe(entry.createdBy);
    expect(sumOf(after?.shares ?? [])).toBe(1500);
  });
});
