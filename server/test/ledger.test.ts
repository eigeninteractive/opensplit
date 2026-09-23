import { describe, expect, it } from "vitest";

import { evenly, expense, freshId, makeGroup, ok, PRIYA, refusal, stub, sumOf } from "./group";

/**
 * Inherits `supabase/tests/01_schema_and_invariant_test.sql`.
 *
 * The invariant it is named for — `sum(payers) = sum(shares) = amount` — was a
 * deferred constraint trigger hung off three tables. It is one function call
 * now, and these are the same cases, asked of the thing that replaced it.
 */
describe("an expense has to add up", () => {
  it("accepts one that does", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const entry = ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1200), ravi.profileId ?? ""));

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

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("unbalanced");
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

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("unbalanced");
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

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  it("refuses an expense with nobody paying and nobody owing", async () => {
    const { groupId, ravi } = await makeGroup();
    const input = expense({ id: freshId("e"), amountMinor: 500, payers: [], shares: [] });

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("unbalanced");
  });

  /**
   * The Postgres version of this test named a member of a *different* group,
   * and needed a three-table join in a trigger to catch it. There is no such
   * member to name here: this object holds one group's members and no others,
   * so a foreign id is simply an id nobody has.
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

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("no_such_member");
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

    expect(refusal(await stub(groupId).upsertEntry(input, ravi.profileId ?? "")).code).toBe("malformed");
  });
});

describe("writing an expense twice", () => {
  it("is idempotent on the id: the second save replaces, never duplicates", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1200), ravi.profileId ?? ""));
    const edited = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1600), ravi.profileId ?? ""));

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

    const first = ok(await object.upsertEntry(input, ravi.profileId ?? ""));
    const again = ok(await object.upsertEntry(input, ravi.profileId ?? ""));

    // A retried push must not travel to every device in the group again.
    expect(again.seq).toBe(first.seq);
    expect(again.updatedAt).toBe(first.updatedAt);
  });

  it("answers a retry that re-minted the id with the expense it already recorded", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const clientKey = freshId("k");

    const first = ok(await object.upsertEntry({ ...evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 700), clientKey }, ravi.profileId ?? ""));
    const retry = ok(await object.upsertEntry({ ...evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 700), clientKey }, ravi.profileId ?? ""));

    expect(retry.id).toBe(first.id);
    expect(retry.seq).toBe(first.seq);
  });

  it("never lets an edit rewrite who recorded it, or when", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 500), ravi.profileId ?? ""));

    // Priya is a placeholder with no account, so Ravi is the only possible
    // author. The point is that there is no parameter to say otherwise.
    const edited = ok(await object.upsertEntry(evenly(id, priya.id, [ravi.id, priya.id], 800), ravi.profileId ?? ""));

    expect(edited.createdBy).toBe(first.createdBy);
    expect(edited.createdAt).toBe(first.createdAt);
  });
});

describe("an edit composed against a version that has moved", () => {
  it("is applied when the base still matches", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    const edited = ok(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 1400), baseSeq: first.seq }, ravi.profileId ?? ""));

    expect(edited.amountMinor).toBe(1400);
  });

  /**
   * Two people fixing a typo should not have to arbitrate. The predicate is
   * about money, not about staleness.
   */
  it("is applied when it is stale but changes nothing about the money", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    ok(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), description: "Dinner at Britto's" }, ravi.profileId ?? ""));

    const late = ok(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), description: "Dinner, Britto's", baseSeq: first.seq }, ravi.profileId ?? ""));

    expect(late.description).toBe("Dinner, Britto's");
  });

  it("is refused when it would move money away from where the server has it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));
    ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 2000), ravi.profileId ?? ""));

    const late = refusal(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), baseSeq: first.seq }, ravi.profileId ?? ""));
    expect(late.code).toBe("stale_base");

    // And the correction somebody else made is still standing.
    const page = ok(await object.changes(ravi.profileId ?? "", 0, 100));
    expect(page.entries.find((entry) => entry.id === id)?.amountMinor).toBe(2000);
  });

  it("is refused when only the shares moved, even though the total did not", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const first = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), ravi.profileId ?? ""));

    ok(
      await object.upsertEntry(
        expense({
          id,
          amountMinor: 1000,
          payers: [{ memberId: ravi.id, amountMinor: 1000 }],
          shares: [
            { memberId: ravi.id, amountMinor: 900, weightMicros: null },
            { memberId: priya.id, amountMinor: 100, weightMicros: null },
          ],
        }),
        ravi.profileId ?? "",
      ),
    );

    expect(refusal(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 1000), baseSeq: first.seq }, ravi.profileId ?? "")).code).toBe("stale_base");
  });
});

describe("deleting an expense", () => {
  it("is soft, and the row stays in the feed", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const deleted = ok(await object.deleteEntry(id, entry.seq, ravi.profileId ?? ""));

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

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 900), ravi.profileId ?? ""));

    expect(refusal(await object.deleteEntry(id, entry.seq, ravi.profileId ?? "")).code).toBe("stale_base");
  });

  it("is idempotent on a retry whose response was lost", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const first = ok(await object.deleteEntry(id, entry.seq, ravi.profileId ?? ""));
    const retry = ok(await object.deleteEntry(id, entry.seq, ravi.profileId ?? ""));

    expect(retry.seq).toBe(first.seq);
    expect(retry.deletedAt).toBe(first.deletedAt);
  });

  it("can be undone, which soft deletion has always implied and never offered", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    const deleted = ok(await object.deleteEntry(id, entry.seq, ravi.profileId ?? ""));
    const restored = ok(await object.restoreEntry(id, deleted.seq, ravi.profileId ?? ""));

    expect(restored.deletedAt).toBeNull();
  });

  it("does not resurrect the expense when somebody saves an edit to it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 600), ravi.profileId ?? ""));
    ok(await object.deleteEntry(id, entry.seq, ravi.profileId ?? ""));

    const edited = ok(await object.upsertEntry({ ...evenly(id, ravi.id, [ravi.id, priya.id], 600), description: "Late edit" }, ravi.profileId ?? ""));
    expect(edited.deletedAt).not.toBeNull();
  });
});

describe("the sequence number", () => {
  it("increases strictly, across every table that carries one", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    const first = ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 400), profile));
    const renamed = ok(await object.update({ name: "Goa, again" }, profile));
    const second = ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 500), profile));

    expect(renamed.seq).toBeGreaterThan(first.seq);
    expect(second.seq).toBeGreaterThan(renamed.seq);
  });

  it("is what the feed pages on, and a cursor never sees the same change twice", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const profile = ravi.profileId ?? "";

    for (let index = 0; index < 5; index += 1) {
      ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 100 + index), profile));
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

    ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 999), profile));

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
    expect(refusal(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 400), PRIYA)).code).toBe("not_member");
  });

  it("is told an unused group id is unused, not forbidden", async () => {
    expect(refusal(await stub(freshId("empty")).changes(PRIYA, 0, 100)).code).toBe("no_group");
  });
});
