import { describe, expect, it } from "vitest";

import { deleteEntry, draftOf, editGroup, editMember, evenly, expense, freshId, makeGroup, ok, PRIYA, RAVI, refusal, restoreEntry, saveEntry, stub, sumOf } from "./group";

/** The invariant and the write path: an expense that does not add up, a hard delete, an idempotent retry, and the stale-base rule. */
describe("an expense has to add up", () => {
  it("accepts one that does", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const entry = ok(await saveEntry(stub(groupId), evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1200), ravi.profileId ?? ""));

    expect(entry.amountMinor).toBe(1200);
    expect(sumOf(entry.payers)).toBe(1200);
    expect(sumOf(entry.shares)).toBe(1200);
  });

  it("refuses shares that fall a paisa short", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const input = expense({
      id: freshId("e"),
      amountMinor: 1200,
      payers: [{ memberId: ravi.id, amountMinor: 1200 }],
      shares: [
        { memberId: ravi.id, amountMinor: 600, weightMicros: null },
        { memberId: priya.id, amountMinor: 599, weightMicros: null },
      ],
    });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  it("refuses payers that fall a paisa short", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const input = expense({
      id: freshId("e"),
      amountMinor: 1200,
      payers: [{ memberId: ravi.id, amountMinor: 1199 }],
      shares: [
        { memberId: ravi.id, amountMinor: 600, weightMicros: null },
        { memberId: priya.id, amountMinor: 600, weightMicros: null },
      ],
    });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  it("refuses shares that overshoot", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const input = expense({
      id: freshId("e"),
      amountMinor: 1200,
      payers: [{ memberId: ravi.id, amountMinor: 1200 }],
      shares: [
        { memberId: ravi.id, amountMinor: 600, weightMicros: null },
        { memberId: priya.id, amountMinor: 601, weightMicros: null },
      ],
    });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  it("refuses an expense with nobody paying and nobody owing", async () => {
    const { groupId, ravi } = await makeGroup();
    const input = expense({ id: freshId("e"), amountMinor: 500, payers: [], shares: [] });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  /**
   * There is no member of another group to name here: this object holds one
   * group's members and no others, so an id from elsewhere is simply an id
   * nobody has. The check is existence rather than a join.
   */
  it("refuses a share for somebody who is not in this group", async () => {
    const { groupId, ravi } = await makeGroup();
    const other = await makeGroup();

    const input = expense({
      id: freshId("e"),
      amountMinor: 400,
      payers: [{ memberId: ravi.id, amountMinor: 400 }],
      shares: [{ memberId: other.priya.id, amountMinor: 400, weightMicros: null }],
    });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("no_such_member");
  });

  it("refuses the same person listed twice in one split", async () => {
    const { groupId, ravi } = await makeGroup();
    const input = expense({
      id: freshId("e"),
      amountMinor: 400,
      payers: [{ memberId: ravi.id, amountMinor: 400 }],
      shares: [
        { memberId: ravi.id, amountMinor: 200, weightMicros: null },
        { memberId: ravi.id, amountMinor: 200, weightMicros: null },
      ],
    });

    expect(refusal(await saveEntry(stub(groupId), input, ravi.profileId ?? "")).code).toBe("malformed");
  });
});

describe("writing an expense twice", () => {
  it("is idempotent on the id: the second save replaces, never duplicates", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1200), ravi.profileId ?? ""));
    const edited = ok(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1600), baseSeq: first.seq }, ravi.profileId ?? ""));

    expect(edited.amountMinor).toBe(1600);
    expect(edited.shares).toHaveLength(2);
    expect(sumOf(edited.shares)).toBe(1600);

    const page = ok(await object.changes(ravi.profileId ?? "", 0, 100));
    expect(page.entries.filter((entry) => entry.id === id)).toHaveLength(1);
  });

  it("spends no sequence number when nothing actually changed", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const input = evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 900);

    const first = ok(await saveEntry(object, input, ravi.profileId ?? ""));
    const again = ok(await saveEntry(object, input, ravi.profileId ?? ""));

    // A retried push must not travel to every device in the group again.
    expect(again.seq).toBe(first.seq);
    expect(again.updatedAt).toBe(first.updatedAt);
  });

  it("never lets an edit rewrite who recorded it, or when", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 500), ravi.profileId ?? ""));

    // Priya is a placeholder with no account, so Ravi is the only possible
    // author. The point is that there is no parameter to say otherwise.
    const edited = ok(await saveEntry(object, { ...evenly(id, priya.id, [ravi.id, priya.id], 800), baseSeq: first.seq }, ravi.profileId ?? ""));

    expect(edited.createdBy).toBe(first.createdBy);
    expect(edited.createdAt).toBe(first.createdAt);
  });
});

describe("an edit composed against a version that has moved", () => {
  it("is applied when the base still matches", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    const edited = ok(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1400), baseSeq: first.seq }, ravi.profileId ?? ""));

    expect(edited.amountMinor).toBe(1400);
  });

  /**
   * The write replaces the whole expense, so a stale one carries the old
   * value of every field it did not touch. Accepting it would silently undo
   * the other edit, whatever the edit was about.
   */
  it("is refused when it is stale, even if it changes nothing about the money", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    ok(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), notes: "Paid on the card", baseSeq: first.seq }, ravi.profileId ?? ""));

    const late = refusal(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), description: "Dinner, Britto's", baseSeq: first.seq }, ravi.profileId ?? ""));
    expect(late.code).toBe("stale_base");

    const page = ok(await object.changes(ravi.profileId ?? "", 0, 100));
    expect(page.entries.find((entry) => entry.id === id)?.notes).toBe("Paid on the card");
  });

  it("is refused when it claims to be new but the row exists", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    expect(refusal(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), description: "Lunch" }, ravi.profileId ?? "")).code).toBe("stale_base");
  });

  it("is answered with the stored row when it sends what is already stored, whatever its base", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const input = evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000);

    // A retry whose first response was lost still holds no base.
    const first = ok(await saveEntry(object, input, ravi.profileId ?? ""));
    expect(ok(await saveEntry(object, input, ravi.profileId ?? "")).seq).toBe(first.seq);
  });

  it("is refused when it would move money away from where the server has it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    ok(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 2000), baseSeq: first.seq }, ravi.profileId ?? ""));

    const late = refusal(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), baseSeq: first.seq }, ravi.profileId ?? ""));
    expect(late.code).toBe("stale_base");

    // And the correction somebody else made is still standing.
    const page = ok(await object.changes(ravi.profileId ?? "", 0, 100));
    expect(page.entries.find((entry) => entry.id === id)?.amountMinor).toBe(2000);
  });
});

describe("deleting an expense", () => {
  it("is soft, and the row stays in the feed", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const deleted = ok(await deleteEntry(object, entry, ravi.profileId ?? ""));

    expect(deleted.deletedAt).not.toBeNull();

    const page = ok(await object.changes(ravi.profileId ?? "", 0, 100));
    expect(page.entries.find((row) => row.id === id)?.deletedAt).not.toBeNull();
  });

  /**
   * Deleting always moves money — every payer and share leaves the live
   * balance — so unlike a prose edit it must be composed against the exact
   * version the device last saw, and a missing base is a refusal.
   */
  it("is refused against a stale base", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    ok(await saveEntry(object, { ...evenly(id, ravi.id, [ravi.id, priya.id], 900), baseSeq: entry.seq }, ravi.profileId ?? ""));

    expect(refusal(await deleteEntry(object, entry, ravi.profileId ?? "")).code).toBe("stale_base");
  });

  it("is idempotent on a retry whose response was lost", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const first = ok(await deleteEntry(object, entry, ravi.profileId ?? ""));
    const retry = ok(await deleteEntry(object, entry, ravi.profileId ?? ""));

    expect(retry.seq).toBe(first.seq);
    expect(retry.deletedAt).toBe(first.deletedAt);
  });

  it("can be undone, which soft deletion has always implied and never offered", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const deleted = ok(await deleteEntry(object, entry, ravi.profileId ?? ""));
    const restored = ok(await restoreEntry(object, deleted, ravi.profileId ?? ""));

    expect(restored.deletedAt).toBeNull();
  });

  it("does not resurrect the expense when somebody saves an edit to it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    ok(await deleteEntry(object, entry, ravi.profileId ?? ""));

    // Composed against the version before the deletion, it would put the money back: stale.
    const late = await saveEntry(object, draftOf(entry, { description: "Late edit" }), ravi.profileId ?? "");
    expect(refusal(late).code).toBe("stale_base");
  });
});

describe("the sequence number", () => {
  it("increases strictly, across every table that carries one", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const first = ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 400), profile));
    const renamed = ok(await editGroup(groupId, profile, { name: "Goa, again" }));
    const second = ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 500), profile));

    expect(renamed.seq).toBeGreaterThan(first.seq);
    expect(second.seq).toBeGreaterThan(renamed.seq);
  });

  it("is what the feed pages on, and a cursor never sees the same change twice", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    for (let index = 0; index < 5; index += 1) {
      ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 100 + index), profile));
    }

    const first = ok(await object.changes(profile, 0, 3));
    expect(first.hasMore).toBe(true);

    const second = ok(await object.changes(profile, first.seq, 100));
    expect(second.hasMore).toBe(false);

    const ids = [...first.entries, ...second.entries].map((entry) => entry.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toHaveLength(5);
  });

  it("carries an entry and its shares in the same page, never split across two", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 999), profile));

    const page = ok(await object.changes(profile, 0, 500));
    for (const entry of page.entries) {
      expect(sumOf(entry.payers)).toBe(entry.amountMinor);
      expect(sumOf(entry.shares)).toBe(entry.amountMinor);
    }
  });
});

describe("a stranger", () => {
  it("cannot read a group they are not in", async () => {
    const { groupId } = await makeGroup();
    expect(refusal(await stub(groupId).changes(PRIYA, 0, 100)).code).toBe("not_member");
  });

  it("cannot write an expense into one", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    expect(refusal(await saveEntry(stub(groupId), evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 400), PRIYA)).code).toBe("not_member");
  });

  it("is told an unused group id is unused, not forbidden", async () => {
    expect(refusal(await stub(freshId("empty")).changes(PRIYA, 0, 100)).code).toBe("no_group");
  });
});

describe("a page of changes", () => {
  it("carries the rows its entries name, even ones changed after them", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    ok(await saveEntry(stub(groupId), evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000), RAVI));
    // Renaming Priya moves her row past the expense naming her.
    ok(await editMember(groupId, priya.id, RAVI, { displayName: "Priya S" }));
    ok(await editGroup(groupId, RAVI, { name: "Goa, renamed" }));

    const first = ok(await stub(groupId).changes(RAVI, 0, 1));
    expect(first.hasMore).toBe(true);
    expect(first.group?.name).toBe("Goa, renamed");
    expect(first.members.map((member) => member.id)).toEqual(expect.arrayContaining([ravi.id, priya.id]));
  });
});

describe("a large page", () => {
  it("reads more expenses than SQLite binds in one statement", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    for (let index = 0; index < 120; index++) {
      ok(await saveEntry(stub(groupId), evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000 + index), RAVI));
    }
    const page = ok(await stub(groupId).changes(RAVI, 0, 500));
    expect(page.entries).toHaveLength(120);
    expect(page.entries.every((entry) => entry.payers.length === 1 && entry.shares.length === 2)).toBe(true);
  });
});

/**
 * One expense among more people than one SQL statement can name: a share is
 * four bound values and a payer three, against a limit of 100 a statement.
 */
describe("an expense shared by a crowd", () => {
  it("is stored whole, every share and every payer", async () => {
    const { groupId, ravi } = await makeGroup();
    const object = stub(groupId);
    const people = [ravi.id];
    for (let index = 0; index < 39; index++) {
      people.push(ok(await object.putMember(freshId("m"), { displayName: `Guest ${index}`, upiVpa: null, leftAt: null }, RAVI)).id);
    }

    const wedding = expense({
      id: freshId("e"),
      amountMinor: 4000,
      payers: people.map((memberId) => ({ memberId, amountMinor: 100 })),
      shares: people.map((memberId) => ({ memberId, amountMinor: 100, weightMicros: 1_000_000 })),
    });
    const stored = ok(await saveEntry(object, wedding, RAVI));

    expect(stored.payers).toHaveLength(40);
    expect(stored.shares).toHaveLength(40);
  });
});
