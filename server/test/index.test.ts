import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import type { Group } from "../src/do/group";
import { finishDeletions } from "../src/forget";
import { collectAbandonedGuests } from "../src/scheduled";
import { BY_INVITE, editMember, freshId, makeAccount, makeGroup, ok, RAVI, stub } from "./group";
import { signInAsGuest } from "./session";

/**
 * The derived index in D1. The group objects are the truth; these tests pin
 * the guarantees that make D1's copy of it trustworthy without any repair job:
 * every write arrives, in order, a late copy changes nothing, and an account
 * deleted at any moment is taken out of every group it was in.
 */

const DAYS = 24 * 60 * 60 * 1000;

async function membership(groupId: string, profileId: string) {
  return env.DB.prepare("select left_at, version from memberships where group_id = ? and profile_id = ?").bind(groupId, profileId).first<{ left_at: string | null; version: number }>();
}

/** D1 stops answering for one table, as far as the object can tell. */
async function withTableAway(table: string, body: () => Promise<void>): Promise<void> {
  await env.DB.prepare(`alter table ${table} rename to ${table}_away`).run();
  try {
    await body();
  } finally {
    await env.DB.prepare(`alter table ${table}_away rename to ${table}`).run();
  }
}

async function outboxOf(groupId: string) {
  return runInDurableObject(stub(groupId), async (_instance: Group, state) => ({
    pending: [...state.storage.sql.exec<{ n: number }>("select count(*) as n from outbox")][0]?.n ?? 0,
    chores: [...state.storage.sql.exec<{ name: string }>("select name from schedule")].map((row) => row.name).sort(),
    alarm: await state.storage.getAlarm(),
  }));
}

describe("when D1 is not answering", () => {
  it("keeps the write, backs off, and converges once D1 is back", async () => {
    const groupId = freshId("outbox");

    await withTableAway("memberships", async () => {
      ok(await stub(groupId).putGroup(groupId, { name: "Offline", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, archivedAt: null, creatorId: `${groupId}-m`, creatorName: "Ravi" }, RAVI));

      // The group itself is fine. The index simply does not know about it yet.
      const waiting = await outboxOf(groupId);
      expect(waiting.pending).toBe(1);
      expect(waiting.chores).toContain("outbox");
    });

    await stub(groupId).runUpkeep(Date.now());
    expect(await membership(groupId, RAVI)).toMatchObject({ left_at: null });
  });

  /** The retry deadline outliving its retry used to leave the group with no alarm at all. */
  it("drops the retry once it succeeds, and the dormancy clock is armed again", async () => {
    const groupId = freshId("outbox");
    await withTableAway("memberships", async () => {
      ok(await stub(groupId).putGroup(groupId, { name: "Offline", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, archivedAt: null, creatorId: `${groupId}-m`, creatorName: "Ravi" }, RAVI));
    });

    await stub(groupId).runUpkeep(Date.now());
    const after = await outboxOf(groupId);

    expect(after.pending).toBe(0);
    expect(after.chores).toEqual(["archive"]);
    expect(after.alarm ?? 0).toBeGreaterThan(Date.now() + 80 * DAYS);
  });

  it("sends a backlog of any size in one go, not twenty at a time", async () => {
    const { groupId } = await makeGroup();
    const object = stub(groupId);

    await withTableAway("link_tokens", async () => {
      for (let index = 0; index < 25; index++) {
        const member = ok(await object.putMember(`${groupId}-p${index}`, { displayName: `P${index}`, upiVpa: null, leftAt: null }, RAVI));
        ok(await object.createInvite(member.id, RAVI));
      }
      expect((await outboxOf(groupId)).pending).toBe(25);
    });

    await object.runUpkeep(Date.now());

    expect((await outboxOf(groupId)).pending).toBe(0);
    const routed = await env.DB.prepare("select count(*) as n from link_tokens where group_id = ?").bind(groupId).first<{ n: number }>();
    expect(routed?.n).toBe(25);
  });
});

describe("the order writes arrive in", () => {
  /** What a copy delayed by a restarted flush looks like when it finally lands. */
  it("ignores a copy older than the one D1 already holds", async () => {
    const priya = await makeAccount("Priya");
    const { groupId, priya: place } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(place.id, RAVI));
    ok(await stub(groupId).join(invite.token, priya, BY_INVITE));

    await env.DB.prepare("update memberships set version = 1000000, left_at = 'newer' where group_id = ? and profile_id = ?").bind(groupId, priya).run();
    ok(await editMember(groupId, place.id, priya, { leftAt: new Date().toISOString() }));

    expect(await membership(groupId, priya)).toEqual({ left_at: "newer", version: 1000000 });
  });

  it("ends where the group ends, however requests to it overlap", async () => {
    const priya = await makeAccount("Priya");
    const { groupId, priya: place } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(place.id, RAVI));
    ok(await stub(groupId).join(invite.token, priya, BY_INVITE));

    // Leaving and being brought back, many times over, all in flight at once.
    const at = new Date().toISOString();
    await Promise.all(Array.from({ length: 12 }, (_, index) => (index % 2 === 0 ? stub(groupId).putMember(place.id, { displayName: "Priya", upiVpa: null, leftAt: at }, priya) : stub(groupId).putMember(place.id, { displayName: "Priya", upiVpa: null, leftAt: null }, RAVI))));

    const truth = ok(await stub(groupId).changes(RAVI, 0, 500)).members.find((member) => member.id === place.id);
    expect((await membership(groupId, priya))?.left_at ?? null).toBe(truth?.leftAt ?? null);
    expect((await outboxOf(groupId)).pending).toBe(0);
  });
});

describe("an account deleted while its membership is on the way", () => {
  it("is refused by D1, and the group turns it into a placeholder itself", async () => {
    const priya = await makeAccount("Priya");
    const { groupId, priya: place } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(place.id, RAVI));

    await withTableAway("memberships", async () => {
      ok(await stub(groupId).join(invite.token, priya, BY_INVITE));
      await env.DB.prepare("delete from user where id = ?").bind(priya).run();
    });
    await stub(groupId).runUpkeep(Date.now());

    expect(await membership(groupId, priya)).toBeNull();
    const member = ok(await stub(groupId).changes(RAVI, 0, 500)).members.find((row) => row.id === place.id);
    expect(member?.profileId).toBeNull();
    expect(member?.displayName).toBe("Priya");
  });

  it("collects the group when that account was the last one in it", async () => {
    const owner = await makeAccount("Asha");
    const groupId = freshId("gone");

    await withTableAway("memberships", async () => {
      ok(await stub(groupId).putGroup(groupId, { name: "Solo", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, archivedAt: null, creatorId: `${groupId}-m`, creatorName: "Asha" }, owner));
      await env.DB.prepare("delete from user where id = ?").bind(owner).run();
    });
    await stub(groupId).runUpkeep(Date.now());

    expect(ok(await stub(groupId).changes(owner, 0, 500)).purgedAt).not.toBeNull();
    const purged = await env.DB.prepare("select group_id from purged_groups where group_id = ?").bind(groupId).first();
    expect(purged).not.toBeNull();
  });
});

describe("a purged group", () => {
  it("accepts no index write afterwards, however late it arrives", async () => {
    const owner = await makeAccount("Asha");
    const { groupId } = await makeGroup({ owner });
    ok(await stub(groupId).createLink(owner));
    expect(await stub(groupId).forgetProfile(owner, null)).toEqual({ forgotten: true, purged: true });

    // A straggler, as if a copy from before the purge were only now being sent.
    await runInDurableObject(stub(groupId), async (_instance: Group, state) => {
      const at = new Date().toISOString();
      state.storage.sql.exec("insert into outbox (kind, payload, created_at) values ('membership', ?, ?)", JSON.stringify({ groupId, profileId: RAVI, leftAt: null, updatedAt: at }), at);
      state.storage.sql.exec("insert into outbox (kind, payload, created_at) values ('link_token', ?, ?)", JSON.stringify({ groupId, token: "late-token", tokenKind: "invite" }), at);
    });
    await stub(groupId).runUpkeep(Date.now());

    const rows = await env.DB.prepare("select (select count(*) from memberships where group_id = ?1) as memberships, (select count(*) from link_tokens where group_id = ?1) as tokens").bind(groupId).first<{ memberships: number; tokens: number }>();
    expect(rows).toEqual({ memberships: 0, tokens: 0 });
  });
});

describe("an account deletion that was interrupted", () => {
  it("is finished by the daily sweep, keeping the name the account had", async () => {
    const asha = await makeAccount("Asha");
    const { groupId, priya: place } = await makeGroup();
    const invite = ok(await stub(groupId).createInvite(place.id, RAVI));
    ok(await stub(groupId).join(invite.token, asha, BY_INVITE));

    // The request deleted the account and died before visiting any group.
    await env.DB.prepare("delete from user where id = ?").bind(asha).run();
    // At least this one; storage is shared within the file, and earlier tests delete accounts too.
    expect(await finishDeletions(env)).toBeGreaterThanOrEqual(1);

    const member = ok(await stub(groupId).changes(RAVI, 0, 500)).members.find((row) => row.id === place.id);
    expect(member?.profileId).toBeNull();
    expect(member?.displayName).toBe("Asha");
    expect(await membership(groupId, asha)).toBeNull();

    const profile = await env.DB.prepare("select display_name, deleted_at from profiles where id = ?").bind(asha).first<{ display_name: string | null; deleted_at: string | null }>();
    expect(profile?.display_name).toBeNull();
    expect(profile?.deleted_at).not.toBeNull();

    // And there is nothing left to finish.
    expect(await finishDeletions(env)).toBe(0);
  });
});

describe("abandoned guests", () => {
  async function age(guestId: string, { created, lastSeen }: { created: number; lastSeen: number }) {
    await env.DB.batch([env.DB.prepare("update user set created_at = ? where id = ?").bind(created, guestId), env.DB.prepare("update session set updated_at = ? where user_id = ?").bind(lastSeen, guestId)]);
  }

  it("are collected after ninety quiet days with no group", async () => {
    const guest = await signInAsGuest();
    await age(guest.id, { created: Date.now() - 200 * DAYS, lastSeen: Date.now() - 100 * DAYS });

    expect(await collectAbandonedGuests(env)).toBe(1);
    expect(await env.DB.prepare("select id from user where id = ?").bind(guest.id).first()).toBeNull();
    expect(await env.DB.prepare("select id from profiles where id = ?").bind(guest.id).first()).toBeNull();
  });

  it("are kept while they still use a session, even with no group", async () => {
    const guest = await signInAsGuest();
    await age(guest.id, { created: Date.now() - 200 * DAYS, lastSeen: Date.now() - 2 * DAYS });

    expect(await collectAbandonedGuests(env)).toBe(0);
  });

  it("are kept while they are in a group, however quiet", async () => {
    const guest = await signInAsGuest();
    await makeGroup({ owner: guest.id });
    await age(guest.id, { created: Date.now() - 200 * DAYS, lastSeen: Date.now() - 100 * DAYS });

    expect(await collectAbandonedGuests(env)).toBe(0);
  });
});
