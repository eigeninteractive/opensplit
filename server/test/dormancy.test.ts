import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import { deleteEntry, editMember, evenly, freshId, makeGroup, makeGroupOfTwo, ok, PRIYA, RAVI, saveEntry, stub } from "./group";

/** Dormancy and account deletion: what an idle group does to itself, and what survives somebody deleting the account that made it. */

const DAYS = 24 * 60 * 60 * 1000;

async function membershipsIn(groupId: string): Promise<{ profile_id: string; left_at: string | null }[]> {
  const rows = await env.DB.prepare("select profile_id, left_at from memberships where group_id = ?").bind(groupId).all<{ profile_id: string; left_at: string | null }>();
  return rows.results;
}

describe("history retention", () => {
  it("neither hides nor deletes a settled group merely because time passes", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    const object = stub(groupId);
    const entry = ok(await saveEntry(object, evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 1000), RAVI));
    ok(await deleteEntry(object, entry, RAVI));
    expect(await object.runUpkeep(Date.now() + 800 * DAYS)).toEqual({ purged: false });
    const page = ok(await object.changes(RAVI, 0, 500));
    expect(page.purgedAt).toBeNull();
    expect(page.entries).toHaveLength(1);
    expect(await membershipsIn(groupId)).toHaveLength(1);
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
