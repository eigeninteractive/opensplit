import { describe, expect, it } from "vitest";

import { isEntryEvent, isGroupEvent, isMemberEvent } from "../src/schemas/ledger";
import { evenly, expense, freshId, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, stub } from "./group";

/**
 * Inherits `supabase/tests/06_activity_test.sql`.
 *
 * The record exists because editing an expense in place is the right model and
 * is silently destructive on its own: somebody who agreed a bill was ₹400 and
 * settled on it would watch their balance move with nothing anywhere to say
 * why, or who did it. That is a trust problem rather than a data one.
 */

async function eventsOf(groupId: string, profileId: string) {
  return ok(await stub(groupId).changes(profileId, 0, 500)).events;
}

describe("recording an expense", () => {
  it("appends one line, not one per row it touched", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1200), RAVI));

    /**
     * The old version fired a deferred trigger once per affected row across
     * three tables — an entry plus four shares was five firings — and needed
     * a payload comparison to collapse them back into one. A single call
     * inside a single transaction writes one.
     */
    const entryEvents = (await eventsOf(groupId, RAVI)).filter((event) => event.kind === "entry");
    expect(entryEvents).toHaveLength(1);
  });

  it("attributes it to whoever actually made it, which is not something they can supply", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 600), PRIYA));

    const line = (await eventsOf(groupId, RAVI)).findLast((event) => event.kind === "entry");
    expect(line?.actorId).toBe(priya.id);
  });

  it("writes nothing at all when a re-saved editor changed nothing", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const input = evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 900);

    ok(await stub(groupId).upsertEntry(input, RAVI));
    const before = (await eventsOf(groupId, RAVI)).length;
    ok(await stub(groupId).upsertEntry(input, RAVI));

    // "Ravi edited nothing" is worse than no feed.
    expect((await eventsOf(groupId, RAVI)).length).toBe(before);
  });

  /**
   * The single most valuable thing to have on the record, because it is the one
   * edit that moves money without moving any number a casual reader would
   * check.
   */
  it("records a split rewritten underneath an unchanged total", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const id = freshId("e");

    ok(await stub(groupId).upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 1000), RAVI));
    const before = (await eventsOf(groupId, RAVI)).filter((event) => event.kind === "entry").length;

    ok(
      await stub(groupId).upsertEntry(
        expense({
          id,
          amountMinor: 1000,
          payers: [{ memberId: ravi.id, amountMinor: 1000 }],
          shares: [
            { memberId: ravi.id, amountMinor: 100, weightMicros: null },
            { memberId: priya.id, amountMinor: 900, weightMicros: null },
          ],
        }),
        RAVI,
      ),
    );

    expect((await eventsOf(groupId, RAVI)).filter((event) => event.kind === "entry")).toHaveLength(before + 1);
  });

  /**
   * The newest snapshot is, by construction, identical to the expense's
   * current row. That redundancy is deliberate: it makes a mismatch a tamper
   * alarm rather than a merge problem, and it lets the history be read without
   * joining against the mutable table it exists to audit.
   */
  it("leaves the newest snapshot identical to the live expense", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const entry = ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 777), RAVI));

    const line = (await eventsOf(groupId, RAVI)).filter(isEntryEvent).findLast((event) => event.subjectId === entry.id);
    if (!line) expect.unreachable("The expense left no snapshot.");

    expect(line.payload.amountMinor).toBe(entry.amountMinor);
    expect(line.payload.description).toBe(entry.description);
    expect(line.payload.deletedAt).toBe(entry.deletedAt);
    expect(line.payload.payers).toEqual(entry.payers);
  });

  it("records a deletion, and the undo after it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const id = freshId("e");

    const entry = ok(await object.upsertEntry(evenly(id, ravi.id, [ravi.id, priya.id], 400), RAVI));
    const deleted = ok(await object.deleteEntry(id, entry.seq, RAVI));
    ok(await object.restoreEntry(id, deleted.seq, RAVI));

    const snapshots = (await eventsOf(groupId, RAVI))
      .filter(isEntryEvent)
      .filter((event) => event.subjectId === id)
      .map((event) => event.payload.deletedAt);

    expect(snapshots).toHaveLength(3);
    expect(snapshots[0]).toBeNull();
    expect(snapshots[1]).not.toBeNull();
    expect(snapshots[2]).toBeNull();
  });
});

describe("member and group life", () => {
  it("says nothing about the group's first member — 'Ravi joined Ravi's flat' is not news", async () => {
    const { groupId } = await makeGroup();
    const kinds = (await eventsOf(groupId, RAVI)).map((event) => event.kind);

    expect(kinds).not.toContain("member_joined");
    expect(kinds).toContain("member_added");
  });

  it("names both sides of a rename, because that is where the whole meaning is", async () => {
    const { groupId, priya } = await makeGroup();
    ok(await stub(groupId).updateMember(priya.id, { displayName: "Priya S" }, RAVI));

    const line = (await eventsOf(groupId, RAVI)).filter(isMemberEvent).findLast((event) => event.kind === "member_renamed");
    expect(line?.payload.displayName).toBe("Priya S");
    expect(line?.payload.previousName).toBe("Priya");
  });

  it("attributes a join to nobody, which is correct rather than a gap", async () => {
    const { groupId, priya } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(priya.id, RAVI));
    ok(await stub(groupId).join(invite.token, PRIYA));

    const line = (await eventsOf(groupId, RAVI)).findLast((event) => event.kind === "member_joined");
    expect(line?.actorId).toBeNull();
    expect(line?.subjectId).toBe(priya.id);
  });

  it("records a rename and an archive from one patch as two things, not one", async () => {
    const { groupId } = await makeGroup();
    ok(await stub(groupId).update({ name: "Goa, closed", archivedAt: new Date().toISOString() }, RAVI));

    const events = await eventsOf(groupId, RAVI);
    const kinds = events.map((event) => event.kind);
    expect(kinds).toContain("group_renamed");
    expect(kinds).toContain("group_archived");

    const renamed = events.filter(isGroupEvent).findLast((event) => event.kind === "group_renamed");
    expect(renamed?.payload.previousName).toBe("Goa trip");
  });

  it("says nothing about a payment handle: it is personal bookkeeping", async () => {
    const { groupId, priya } = await makeGroup();
    const before = (await eventsOf(groupId, RAVI)).length;

    ok(await stub(groupId).updateMember(priya.id, { upiVpa: "priya@okaxis" }, RAVI));
    expect((await eventsOf(groupId, RAVI)).length).toBe(before);
  });
});

describe("an archived group that comes back", () => {
  it("records the expense that revived it, not 'somebody restored the group'", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    ok(await object.update({ archivedAt: new Date().toISOString() }, RAVI));
    ok(await object.upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 300), RAVI));

    const kinds = (await eventsOf(groupId, RAVI)).map((event) => event.kind);
    expect(kinds).toContain("group_archived");
    expect(kinds).not.toContain("group_restored");
    expect(kinds.at(-1)).toBe("entry");

    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.group?.archivedAt).toBeNull();
  });

  it("but records somebody un-archiving it on purpose", async () => {
    const { groupId } = await makeGroup();
    const object = stub(groupId);

    ok(await object.update({ archivedAt: new Date().toISOString() }, RAVI));
    ok(await object.update({ archivedAt: null }, RAVI));

    expect((await eventsOf(groupId, RAVI)).map((event) => event.kind)).toContain("group_restored");
  });
});
