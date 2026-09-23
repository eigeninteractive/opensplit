import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { Group } from "../src/do/group";
import type { append } from "../src/do/group/events";
import { kindOf, refusalCodes, statusFor } from "../src/do/group/refusal";
import { isMemberEvent } from "../src/schemas/ledger";
import { evenly, freshId, makeGroup, ok, RAVI, stub } from "./group";

const DAYS = 24 * 60 * 60 * 1000;

/**
 * The object as a Cloudflare object, rather than as a ledger: its migrations,
 * its alarm, and the type its methods actually present across the RPC
 * boundary.
 *
 * None of this has a pgTAP ancestor. It is the part of the design that is new,
 * which is exactly the part with no existing tests to inherit.
 */

describe("the schema this object migrates itself to", () => {
  /**
   * Migrations here are lazy and per object — a group nobody has touched for
   * six months migrates on its next open — which is the property that makes
   * re-application worth testing at all. A `wrangler d1 migrations apply`
   * runs once against one database; this runs on every open of every object,
   * forever.
   */
  it("is applied exactly once, however many times the object is opened", async () => {
    const { groupId, ravi, priya } = await makeGroup();
    ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 450), RAVI));

    // Several more opens, each of which re-enters the constructor's
    // blockConcurrencyWhile.
    for (let index = 0; index < 3; index += 1) await stub(groupId).ping();

    await runInDurableObject(stub(groupId), async (_instance: Group, state) => {
      const applied = [...state.storage.sql.exec<{ n: number }>("select count(*) as n from __drizzle_migrations")];
      expect(applied[0]?.n).toBe(1);

      const entries = [...state.storage.sql.exec<{ n: number }>("select count(*) as n from entries")];
      expect(entries[0]?.n).toBe(1);
    });
  });

  /**
   * Nothing enforces this at runtime, and it is the rule the whole
   * authorization model rests on: this object holds one group's rows, so
   * "in this group" is a statement about which database you are in.
   */
  it("has no group_id column anywhere, because the object is the group", async () => {
    const { groupId } = await makeGroup();

    await runInDurableObject(stub(groupId), async (_instance: Group, state) => {
      const columns = [...state.storage.sql.exec<{ name: string }>("select name from pragma_table_info('entries') union all select name from pragma_table_info('members') union all select name from pragma_table_info('events')")];

      expect(columns.map((column) => column.name)).not.toContain("group_id");
    });
  });
});

describe("the one alarm", () => {
  it("is armed for the dormancy clock as soon as there is a group", async () => {
    const { groupId } = await makeGroup();

    await runInDurableObject(stub(groupId), async (_instance: Group, state) => {
      const at = await state.storage.getAlarm();
      expect(at).not.toBeNull();
      expect(at ?? 0).toBeGreaterThan(Date.now() + 80 * DAYS);
      expect(at ?? 0).toBeLessThan(Date.now() + 100 * DAYS);
    });
  });

  it("is pushed out again by every expense, so a group in use is never put away", async () => {
    const { groupId, ravi, priya } = await makeGroup();

    const before = await runInDurableObject(stub(groupId), async (_instance: Group, state) => state.storage.getAlarm());
    await new Promise((resolve) => setTimeout(resolve, 5));
    ok(await stub(groupId).upsertEntry(evenly(freshId("e"), ravi.id, [ravi.id, priya.id], 300), RAVI));

    const after = await runInDurableObject(stub(groupId), async (_instance: Group, state) => state.storage.getAlarm());
    expect(after ?? 0).toBeGreaterThan(before ?? 0);
  });

  it("finds nothing to do when it fires early, and simply re-arms", async () => {
    const { groupId } = await makeGroup();

    await runInDurableObject(stub(groupId), async (_instance: Group, state) => {
      await state.storage.setAlarm(Date.now() + 10);
    });

    expect(await runDurableObjectAlarm(stub(groupId))).toBe(true);
    expect(ok(await stub(groupId).changes(RAVI, 0, 100)).group?.archivedAt).toBeNull();
  });
});

describe("the derived index in D1, when D1 is not answering", () => {
  /**
   * The failure the outbox exists for. A `fetch` cannot join a
   * `transactionSync`, so an inline D1 write that failed would leave the index
   * behind the object with nothing left to retry it — the object would have
   * committed and moved on.
   */
  it("keeps the write, backs off, and converges once D1 is back", async () => {
    const groupId = freshId("outbox");
    await env.DB.prepare("drop table memberships").run();

    const created = await stub(groupId).create({ id: groupId, name: "Offline", defaultCurrency: "INR", isDirect: false, simplifyDebts: true, memberId: `${groupId}-m`, displayName: "Ravi" }, RAVI);

    // The group itself is fine. The index simply does not know about it yet.
    expect(created.ok).toBe(true);

    const pending = await runInDurableObject(stub(groupId), async (_instance: Group, state) => [...state.storage.sql.exec<{ n: number; attempts: number }>("select count(*) as n, max(attempts) as attempts from outbox")]);

    expect(pending[0]?.n).toBe(1);
    expect(pending[0]?.attempts).toBeGreaterThan(0);

    await env.DB.prepare("create table memberships (profile_id text not null, group_id text not null, left_at text, updated_at text not null, primary key (profile_id, group_id))").run();
    await stub(groupId).runUpkeep(Date.now());

    const rows = await env.DB.prepare("select profile_id from memberships where group_id = ?").bind(groupId).all<{ profile_id: string }>();
    expect(rows.results.map((row) => row.profile_id)).toEqual([RAVI]);
  });
});

describe("what the RPC boundary actually carries", () => {
  /**
   * A guard against a failure that costs nothing at runtime and everything at
   * review time.
   *
   * workerd types an RPC method's return by what it can structured-clone, and
   * `unknown` is not that. A `Result<ChangePage>` whose event payload was
   * `Record<string, unknown>` therefore lost its entire success branch: every
   * `changes()` call typed as the refusal alone, every read of a page was
   * `unknown`, and nothing failed — the tests passed, the handler compiled.
   *
   * This is a type assertion rather than an assertion about a value, and the
   * `npm run typecheck` over `test/` is what runs it.
   */
  it("includes the success branch of every method that returns one", async () => {
    const object = env.GROUP.getByName("type-check");

    type Success<T> = Extract<Awaited<T>, { ok: true }>;

    expectTypeOf<Success<ReturnType<typeof object.changes>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.upsertEntry>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.create>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.updateMember>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.createInvite>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.peekLink>>>().not.toBeNever();
    expectTypeOf<Success<ReturnType<typeof object.placeholders>>>().not.toBeNever();

    // And the page really does arrive whole at runtime, not just in the types.
    const { groupId } = await makeGroup();
    const page = ok(await stub(groupId).changes(RAVI, 0, 100));
    const added = page.events.filter(isMemberEvent).at(0);
    expect(added?.payload.displayName).toBe("Priya");
  });

  /**
   * The pairing between an event's kind and its payload, asserted the only way
   * a type rule can be: by writing the wrong one and requiring the compiler to
   * object. If this stops being an error, `@ts-expect-error` becomes one.
   */
  it("will not let an event be appended with the wrong kind of payload", () => {
    type Appendable = Parameters<typeof append>[1];

    const wrong = {
      seq: 1,
      now: "2026-09-23T00:00:00.000Z",
      actorId: null,
      kind: "member_renamed",
      subjectId: "member-1",
      // @ts-expect-error a member event carries a name, not a group's name
      payload: { name: "Goa trip", previousName: null },
    } satisfies Appendable;

    expect(wrong.kind).toBe("member_renamed");
  });
});

describe("what a refusal tells a client to do", () => {
  /**
   * The rule the plan originally stated — "409 is a conflict a person
   * resolves, other 4xx are permanent" — is not true of this API, and a client
   * that believed it would spin on the outbox forever.
   */
  it("does not let the status code stand in for the retry decision", () => {
    const conflicts = refusalCodes.filter((code) => statusFor(code) === 409);

    // Five codes are 409, and 409 is right for all of them: the request
    // conflicts with the resource's current state.
    expect(conflicts.length).toBeGreaterThan(1);

    // Only one of them is worth re-composing and sending again.
    expect(conflicts.filter((code) => kindOf(code) === "stale")).toEqual(["stale_base"]);
  });

  it("gives every code a status and a retry kind, so a new one cannot be forgotten", () => {
    for (const code of refusalCodes) {
      expect(statusFor(code)).toBeGreaterThanOrEqual(400);
      expect(["stale", "permanent"]).toContain(kindOf(code));
    }
  });
});
