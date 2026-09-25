import { describe, expect, it } from "vitest";

import { evenly, freshId, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, refusal, stub, ZARA } from "./group";

/**
 * What one member of a group can do to another, which is a different question
 * from what a stranger can do and has a much less obvious answer.
 *
 * There is nothing here about reaching the rows directly, because there is no
 * way to: the only door is a method on this object, and the methods that would
 * be dangerous do not exist. What is left is the part that is about people,
 * and it is the part with teeth — an unguarded update over a group's member
 * rows grants every one of these.
 */

describe("what a member may change about somebody else", () => {
  it("never their payment handle — the one field here that can redirect real money", async () => {
    const { groupId, priya } = await makeGroupOfTwo();
    const refused = refusal(await stub(groupId).updateMember(priya.id, { upiVpa: "ravi@okhdfcbank" }, RAVI));

    expect(refused.code).toBe("forbidden");
    expect(refused.message).toContain("Priya");
  });

  it("never their name, once they have an account of their own", async () => {
    const { groupId, priya } = await makeGroupOfTwo();
    expect(refusal(await stub(groupId).updateMember(priya.id, { displayName: "Someone else" }, RAVI)).code).toBe("forbidden");
  });

  /**
   * This is the exception, and it is deliberate. Somebody has to be able to
   * name and pay a person who has never opened the app, which is the entire
   * point of placeholders existing.
   */
  it("but a placeholder stays editable by anybody in the group", async () => {
    const { groupId, priya } = await makeGroup();
    const renamed = ok(await stub(groupId).updateMember(priya.id, { displayName: "Priya S", upiVpa: "priya@okaxis" }, RAVI));

    expect(renamed.displayName).toBe("Priya S");
    expect(renamed.upiVpa).toBe("priya@okaxis");
  });

  it("and your own name and handle stay yours to set", async () => {
    const { groupId, ravi } = await makeGroupOfTwo();
    const updated = ok(await stub(groupId).updateMember(ravi.id, { displayName: "Ravi K", upiVpa: "ravi@okicici" }, RAVI));

    expect(updated.displayName).toBe("Ravi K");
    expect(updated.upiVpa).toBe("ravi@okicici");
  });

  /**
   * There is no parameter for `profileId` on any patch, so evicting somebody
   * by blanking their account is not a rule that had to be written — it is a
   * statement nothing in this object makes.
   */
  it("and nothing they can send blanks somebody's account out from under them", async () => {
    const { groupId, priya } = await makeGroupOfTwo();
    const patched = ok(await stub(groupId).updateMember(priya.id, { profileId: null } as never, RAVI));

    expect(patched.profileId).toBe(PRIYA);
  });
});

describe("leaving, and being removed", () => {
  it("is always yours to do, settled or not", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000), RAVI));

    const left = ok(await object.updateMember(ravi.id, { leftAt: new Date().toISOString() }, RAVI));
    expect(left.leftAt).not.toBeNull();
  });

  /**
   * Removal is not only a removal: membership is what lets you read the group,
   * so it also cuts somebody off — and the person most worth cutting off is
   * exactly the one still owed money, or the one still chasing you for it.
   */
  it("but somebody who still owes or is owed cannot be removed by anybody else", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000), RAVI));

    const refused = refusal(await object.updateMember(priya.id, { leftAt: new Date().toISOString() }, RAVI));
    expect(refused.code).toBe("not_settled");
    expect(refused.message).toContain("Priya");
  });

  it("and a settled one can be: with nothing owed either way it is just tidying up", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    const id = freshId("e");
    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), RAVI));
    ok(await object.deleteEntry(id, entry.seq, RAVI));

    expect(ok(await object.updateMember(priya.id, { leftAt: new Date().toISOString() }, RAVI)).leftAt).not.toBeNull();
  });

  /**
   * Neither of the obvious answers is right, and this is the third one. See
   * `changes.ts`.
   */
  it("leaves the removed member reading up to their own removal, and no further", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    const removed = ok(await object.updateMember(priya.id, { leftAt: new Date().toISOString() }, RAVI));

    const hers = ok(await object.changes(PRIYA, 0, 500));
    expect(hers.seq).toBe(removed.seq);
    expect(hers.members.find((member) => member.id === priya.id)?.leftAt).not.toBeNull();

    ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id], 700), RAVI));

    const after = ok(await object.changes(PRIYA, hers.seq, 500));
    expect(after.entries).toHaveLength(0);
    expect(after.hasMore).toBe(false);
  });

  it("and stops them writing to it at all", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    ok(await object.updateMember(priya.id, { leftAt: new Date().toISOString() }, RAVI));
    expect(refusal(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id], 300), PRIYA)).code).toBe("not_member");
  });
});

describe("the group itself", () => {
  it("can be renamed by any member, including one who did not create it", async () => {
    const { groupId } = await makeGroupOfTwo();
    expect(ok(await stub(groupId).update({ name: "Goa, take two" }, PRIYA)).name).toBe("Goa, take two");
  });

  /**
   * `id`, `createdAt` and `createdBy` are not fields on the patch, so they
   * cannot be sent. Were they — as they would be on a full-row upsert — this
   * one call would re-identify a group, back-date it into the dormancy purge,
   * and reassign its authorship.
   */
  it("cannot be re-identified, back-dated, or have its authorship reassigned", async () => {
    const { groupId, group } = await makeGroupOfTwo();
    const patched = ok(await stub(groupId).update({ id: freshId("x"), createdAt: "2000-01-01T00:00:00.000Z", createdBy: "someone-else" } as never, PRIYA));

    expect(patched.id).toBe(group.id);
    expect(patched.createdAt).toBe(group.createdAt);
    expect(patched.createdBy).toBe(group.createdBy);
  });

  it("cannot be claimed at an id somebody else is already using", async () => {
    const { groupId } = await makeGroup();
    const refused = refusal(await stub(groupId).create({ id: groupId, name: "Mine now", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, memberId: freshId("m"), displayName: "Zara" }, ZARA));

    expect(refused.code).toBe("group_exists");
  });

  it("answers the account that made it idempotently, for a retry whose response was lost", async () => {
    const { groupId, group } = await makeGroup();
    const again = ok(await stub(groupId).create({ id: groupId, name: "Goa trip", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, memberId: `${groupId}-ravi`, displayName: "Ravi" }, RAVI));

    expect(again.seq).toBe(group.seq);
  });
});

describe("an expense", () => {
  /**
   * A shared id space makes this a takeover: name an expense belonging to a
   * group you have never been in, and an upsert on its id rewrites the amount,
   * the description and every share in place. There is no shared id space here
   * — this object holds one group's rows and an id from another names nothing.
   */
  it("in another group cannot be hijacked by upserting its id", async () => {
    const victim = await makeGroup();
    const attacker = await makeGroup({ owner: ZARA });

    const id = freshId("e");
    const original = ok(await stub(victim.groupId).upsertEntry(evenly(id, victim.ravi.id, [victim.ravi.id, victim.priya.id], 5000), RAVI));

    // Zara writes to *her* group's object using the same id. It lands there,
    // which is correct, and has no bearing on the expense that already exists
    // somewhere else under the same name.
    ok(await stub(attacker.groupId).upsertEntry(evenly(id, attacker.ravi.id, [attacker.ravi.id], 1), ZARA));

    const page = ok(await stub(victim.groupId).changes(RAVI, 0, 500));
    const after = page.entries.find((entry) => entry.id === id);
    expect(after?.amountMinor).toBe(original.amountMinor);
    expect(after?.seq).toBe(original.seq);
  });

  it("is recorded under the caller's own name, whatever else they send", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();

    const entry = ok(await stub(groupId).upsertEntry({ ...evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 800), createdBy: ravi.id } as never, PRIYA));

    expect(entry.createdBy).toBe(priya.id);
  });

  it("cannot be back-dated into somebody else's history", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();

    const entry = ok(await stub(groupId).upsertEntry({ ...evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 800), createdAt: "2001-01-01T00:00:00.000Z", updatedAt: "3000-01-01T00:00:00.000Z" } as never, RAVI));

    /**
     * The year-3000 timestamp is the one that used to matter. `updated_at` was
     * the sync cursor, so a client that could write it could pin every other
     * device's cursor in the far future and stop the group syncing for good.
     * It is descriptive now — `seq` is the cursor — but it is still not the
     * client's to write.
     */
    expect(Date.parse(entry.createdAt)).toBeGreaterThan(Date.parse("2020-01-01T00:00:00.000Z"));
    expect(Date.parse(entry.updatedAt)).toBeLessThan(Date.parse("2100-01-01T00:00:00.000Z"));
  });
});
