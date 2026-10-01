import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import { deleteEntry, editMember, evenly, freshId, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, refusal, saveEntry, stub } from "./group";

/** Dormancy and account deletion: what an idle group does to itself, and what survives somebody deleting the account that made it. */

const DAYS = 24 * 60 * 60 * 1000;

async function membershipsIn(groupId: string): Promise<{ profile_id: string; left_at: string | null }[]> {
  const rows = await env.DB.prepare("select profile_id, left_at from memberships where group_id = ?").bind(groupId).all<{ profile_id: string; left_at: string | null }>();
  return rows.results;
}

describe("a group that goes quiet", () => {
  it("is put away after three months", async () => {
    const { groupId } = await makeGroup();
    const outcome = await stub(groupId).runUpkeep(Date.now() + 100 * DAYS);

    expect(outcome.archived).toBe(true);
    expect(ok(await stub(groupId).changes(RAVI, 0, 500)).group?.archivedAt).not.toBeNull();
  });

  it("is left alone while somebody is still using it", async () => {
    const { groupId } = await makeGroup();
    const outcome = await stub(groupId).runUpkeep(Date.now() + 10 * DAYS);

    expect(outcome.archived).toBe(false);
  });

  /**
   * Archiving is reversible precisely so that being wrong about it costs the
   * people in the group nothing.
   */
  it("comes back by itself the moment somebody adds an expense, with nothing to undo", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    await object.runUpkeep(Date.now() + 100 * DAYS);
    ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 400), RAVI));

    expect(ok(await object.changes(RAVI, 0, 500)).group?.archivedAt).toBeNull();
  });

  it("tells the record that nobody archived it", async () => {
    const { groupId } = await makeGroup();
    await stub(groupId).runUpkeep(Date.now() + 100 * DAYS);

    const events = ok(await stub(groupId).changes(RAVI, 0, 500)).events;
    const archived = events.findLast((event) => event.kind === "group_archived");
    expect(archived?.actorId).toBeNull();
  });
});

describe("a group long dead", () => {
  /**
   * The settled check is the whole safety of collection. The most likely
   * reason a group goes quiet with a balance outstanding is that the debt is
   * disputed or forgotten, which is exactly when erasing the record is worst.
   */
  it("is never collected while anybody still owes anybody anything", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000), RAVI));

    const outcome = await object.runUpkeep(Date.now() + 800 * DAYS);
    expect(outcome.purged).toBe(false);
    expect(ok(await object.changes(RAVI, 0, 500)).group).not.toBeNull();
  });

  it("is collected once it is settled, and says so in the feed", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    const id = freshId("e");
    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 1000), RAVI));
    ok(await deleteEntry(object, entry, RAVI));

    const outcome = await object.runUpkeep(Date.now() + 800 * DAYS);
    expect(outcome.purged).toBe(true);

    /**
     * The end of a group is a change with a sequence number, which means it
     * travels. Deleting the rows and telling nobody would leave a phone that
     * had synced the group holding it forever.
     */
    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.purgedAt).not.toBeNull();
    expect(page.group).toBeNull();
    expect(page.entries).toHaveLength(0);
    expect(page.members).toHaveLength(0);
  });

  it("stops answering writes afterwards, and says which kind of nothing it is", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    const id = freshId("e");
    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 500), RAVI));
    ok(await deleteEntry(object, entry, RAVI));
    await object.runUpkeep(Date.now() + 800 * DAYS);

    expect(refusal(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id], 100), RAVI)).code).toBe("group_purged");
  });

  it("takes its rows out of the membership index with it", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    expect(await membershipsIn(groupId)).toHaveLength(1);

    const id = freshId("e");
    const entry = ok(await saveEntry(object, evenly(id, ravi.id, [ravi.id, priya.id], 500), RAVI));
    ok(await deleteEntry(object, entry, RAVI));
    await object.runUpkeep(Date.now() + 800 * DAYS);

    expect(await membershipsIn(groupId)).toHaveLength(0);
  });
});

describe("the membership index in D1", () => {
  it("learns about the creator as soon as the group exists", async () => {
    const { groupId } = await makeGroup();
    expect(await membershipsIn(groupId)).toEqual([{ profile_id: RAVI, left_at: null }]);
  });

  it("learns about somebody who claims a place", async () => {
    const { groupId } = await makeGroupOfTwo();
    const rows = await membershipsIn(groupId);

    expect(rows.map((row) => row.profile_id).sort()).toEqual([RAVI, PRIYA].sort());
  });

  it("learns when somebody leaves, rather than losing the row", async () => {
    const { groupId, priya } = await makeGroupOfTwo();
    ok(await editMember(groupId, priya.id, PRIYA, { leftAt: new Date().toISOString() }));

    const rows = await membershipsIn(groupId);
    expect(rows.find((row) => row.profile_id === PRIYA)?.left_at).not.toBeNull();
  });
});

describe("deleting an account", () => {
  it("leaves the person in other people's groups, as a placeholder with their name", async () => {
    const { groupId, ravi, priya } = await makeGroupOfTwo();
    const object = stub(groupId);

    ok(await saveEntry(object, evenly(freshId("e"), priya.id, [ravi.id, priya.id], 1000), PRIYA));
    const before = ok(await object.changes(RAVI, 0, 500));

    expect(await object.forgetProfile(PRIYA, null)).toEqual({ forgotten: true, purged: false });

    const after = ok(await object.changes(RAVI, 0, 500));
    const demoted = after.members.find((member) => member.id === priya.id);

    expect(demoted?.profileId).toBeNull();
    expect(demoted?.displayName).toBe("Priya");

    /**
     * Money Priya paid and money she owes are facts about Ravi's group as much
     * as hers; erasing her side would leave his balances wrong with nothing to
     * explain it.
     */
    expect(after.entries.map((entry) => ({ id: entry.id, payers: entry.payers, shares: entry.shares }))).toEqual(before.entries.map((entry) => ({ id: entry.id, payers: entry.payers, shares: entry.shares })));
  });

  /**
   * Nobody left can ever read this group again, so holding somebody's expense
   * descriptions forever in a group with no living reader is the opposite of
   * what was asked for.
   */
  it("collects a group nobody could still read", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);

    ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 600), RAVI));
    expect(await object.forgetProfile(RAVI, null)).toEqual({ forgotten: true, purged: true });

    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.purgedAt).not.toBeNull();
    expect(await membershipsIn(groupId)).toHaveLength(0);
  });

  it("is quietly true of a group the account was never in", async () => {
    const { groupId } = await makeGroup();
    expect(await stub(groupId).forgetProfile("00000000-0000-4000-8000-000000000000", null)).toEqual({ forgotten: false, purged: false });
  });
});
