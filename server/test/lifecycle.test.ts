import { describe, expect, it } from "vitest";
import { BY_INVITE, deleteEntry, draftOf, editGroup, editMember, evenly, freshId, makeAccount, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, refusal, saveEntry, stub } from "./group";

const now = () => new Date().toISOString();

describe("leaving a group", () => {
  it("deletes the last account's settled group, including deleted expenses and join links", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const entry = ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id], 100), RAVI));
    ok(await deleteEntry(object, entry, RAVI));
    const link = ok(await object.createLink(RAVI));
    const input = { displayName: ravi.displayName, upiVpa: ravi.upiVpa, leftAt: now(), baseSeq: ravi.seq };
    expect(ok(await object.putMember(ravi.id, input, RAVI)).leftAt).not.toBeNull();
    // A lost reply is resolved by the tombstone; it must never recreate the group.
    expect(refusal(await object.putMember(ravi.id, input, RAVI)).code).toBe("group_purged");
    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.purgedAt).not.toBeNull();
    expect(page.group).toBeNull();
    expect(page.entries).toEqual([]);
    expect(page.members).toEqual([]);
    expect(refusal(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id], 100), RAVI)).code).toBe("group_purged");
    expect(refusal(await object.join(link.token, PRIYA, { memberId: null, displayName: "Priya" })).code).toBe("group_purged");
  });

  it("does not strand debts between placeholders when the last account tries to leave", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const arun = ok(await object.putMember(freshId("m"), { displayName: "Arun", upiVpa: null, leftAt: null, baseSeq: null }, RAVI));
    ok(await saveEntry(object, evenly(freshId("e"), priya.id, [priya.id, arun.id], 100), RAVI));
    expect(refusal(await editMember(groupId, ravi.id, RAVI, { leftAt: now() })).code).toBe("not_settled");
    expect(ok(await object.changes(RAVI, 0, 500)).group?.id).toBe(groupId);
  });

  it("ends access, retains shared records, and restores current access only through a valid link", async () => {
    const { groupId, ravi } = await makeGroupOfTwo();
    const object = stub(groupId);
    const entry = ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id], 200), RAVI));
    const input = { displayName: ravi.displayName, upiVpa: ravi.upiVpa, leftAt: now(), baseSeq: ravi.seq };
    const left = ok(await object.putMember(ravi.id, input, RAVI));
    expect(ok(await object.putMember(ravi.id, input, RAVI))).toEqual(left);
    expect(refusal(await object.changes(RAVI, 0, 500)).code).toBe("not_member");
    expect(refusal(await object.createLink(RAVI)).code).toBe("not_member");
    expect(ok(await object.changes(PRIYA, 0, 500)).entries).toContainEqual(entry);
    ok(await editGroup(groupId, PRIYA, { name: "Current name" }));
    ok(await saveEntry(object, draftOf(entry, { description: "Current expense" }), PRIYA));
    expect(refusal(await object.changes(RAVI, 0, 1)).code).toBe("not_member");
    const link = ok(await object.createLink(PRIYA));
    const joined = ok(await object.join(link.token, RAVI, { memberId: null, displayName: "Ravi" }));
    expect(joined.member.id).toBe(ravi.id);
    expect(joined.member.leftAt).toBeNull();
    const current = ok(await object.changes(RAVI, 0, 500));
    expect(current.group?.name).toBe("Current name");
    expect(current.entries[0]?.description).toBe("Current expense");
  });

  it("refuses stale member and group replacements without undoing newer settings", async () => {
    const { groupId, priya, group } = await makeGroup();
    ok(await editGroup(groupId, RAVI, { name: "Latest name", baseSeq: group.seq }));
    expect(refusal(await editGroup(groupId, RAVI, { name: "Stale name", baseSeq: group.seq })).code).toBe("stale_base");
    ok(await editMember(groupId, priya.id, RAVI, { displayName: "New name", baseSeq: priya.seq }));
    expect(refusal(await editMember(groupId, priya.id, RAVI, { displayName: "Old name", baseSeq: priya.seq })).code).toBe("stale_base");
  });
});

describe("account ownership", () => {
  it("does not give former guests access when transferring to an account", async () => {
    const { groupId, ravi } = await makeGroupOfTwo();
    const object = stub(groupId);
    ok(await editMember(groupId, ravi.id, RAVI, { leftAt: now() }));
    const heir = await makeAccount("Ravi's saved account");
    expect(await object.handOver(RAVI, heir)).toEqual({ forgotten: true, purged: false });
    expect(refusal(await object.changes(heir, 0, 500)).code).toBe("not_member");
    expect(refusal(await object.changes(RAVI, 0, 500)).code).toBe("not_member");
    expect(await object.forgetProfile(PRIYA, "Priya")).toEqual({ forgotten: true, purged: true });
  });

  it("transfers an active guest's access to an existing account that previously left", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);
    ok(await editMember(groupId, ravi.id, RAVI, { leftAt: now() }));
    const entry = ok(await saveEntry(object, evenly(freshId("e"), priya.id, [priya.id], 200), PRIYA));
    expect(await object.handOver(PRIYA, RAVI)).toEqual({ forgotten: true, purged: false });
    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.members.find((member) => member.id === ravi.id)?.leftAt).toBeNull();
    expect(page.members.find((member) => member.id === priya.id)?.profileId).toBeNull();
    expect(page.entries).toContainEqual(entry);
  });

  it("deletes the group when the last active account is deleted even if former members remain", async () => {
    const { groupId, ravi } = await makeGroupOfTwo();
    const object = stub(groupId);
    ok(await editMember(groupId, ravi.id, RAVI, { leftAt: now() }));
    expect(await object.forgetProfile(PRIYA, "Priya Last Name")).toEqual({ forgotten: true, purged: true });
    expect(ok(await object.changes(RAVI, 0, 500)).purgedAt).not.toBeNull();
  });

  it("leaves an ordinary active placeholder that can receive expenses and be claimed", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);
    await object.forgetProfile(PRIYA, "Priya Last Name");
    const member = ok(await object.changes(RAVI, 0, 500)).members.find((row) => row.id === priya.id);
    expect(member).toMatchObject({ profileId: null, leftAt: null, displayName: "Priya Last Name" });
    ok(await saveEntry(object, evenly(freshId("e"), priya.id, [ravi.id, priya.id], 100), RAVI));
    const heir = await makeAccount("Another account");
    const invite = ok(await object.createInvite(priya.id, RAVI));
    expect(ok(await object.join(invite.token, heir, BY_INVITE)).member.id).toBe(priya.id);
  });
});
