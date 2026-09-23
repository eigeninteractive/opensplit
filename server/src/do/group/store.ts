import { and, eq, isNull, sql } from "drizzle-orm";
import type { DrizzleSqliteDODatabase } from "drizzle-orm/durable-sqlite";

import * as schema from "../../db/group/schema";
import { refuse } from "./refusal";

export type GroupDb = DrizzleSqliteDODatabase<typeof schema>;

/**
 * A transaction handle, derived from the driver rather than named by hand.
 *
 * Every query in this object runs inside `db.transaction()`, including the
 * read-only ones. `drizzle-orm/durable-sqlite` maps that onto
 * `ctx.storage.transactionSync()`, which is synchronous and in-process, so a
 * read transaction costs a savepoint and nothing else — and having one code
 * path means a helper can be used from a read or a write without two versions
 * of it existing.
 */
export type Tx = Parameters<Parameters<GroupDb["transaction"]>[0]>[0];

export type MetaRow = typeof schema.meta.$inferSelect;
export type MemberRow = typeof schema.members.$inferSelect;
export type EntryRow = typeof schema.entries.$inferSelect;

/**
 * The next sequence number, allocated once per committed change.
 *
 * One statement, so there is no read-then-write to lose: the row is created on
 * first use and incremented forever after. It lives in SQLite rather than in
 * the object's key-value storage because it has to be inside the same
 * transaction as the rows it stamps — a counter that advanced when the write
 * rolled back would leave a gap, and a counter that did not advance when the
 * write committed would hand the same number to two changes and hide the
 * second from every device that had already read the first.
 */
export function nextSeq(tx: Tx): number {
  const row = tx.get<{ value: number }>(
    sql`insert into ${schema.counter} (name, value) values ('seq', 1)
        on conflict(name) do update set value = ${schema.counter.value} + 1
        returning value`,
  );
  return row.value;
}

/** The highest sequence number this group has ever issued. */
export function currentSeq(tx: Tx): number {
  const row = tx.select({ value: schema.counter.value }).from(schema.counter).where(eq(schema.counter.name, "seq")).get();
  return row?.value ?? 0;
}

export function findMeta(tx: Tx): MetaRow | undefined {
  return tx.select().from(schema.meta).get();
}

export function findTombstone(tx: Tx): { groupId: string; purgedAt: string; seq: number } | undefined {
  return tx.select({ groupId: schema.tombstone.groupId, purgedAt: schema.tombstone.purgedAt, seq: schema.tombstone.seq }).from(schema.tombstone).get();
}

/**
 * The group, or a refusal that says which kind of nothing this is.
 *
 * A Durable Object always exists — `getByName` never fails — so "is there a
 * group here" is a question about rows rather than about addressing. The three
 * answers are genuinely different to a client: an id nobody has used, an id
 * whose group was collected, and a live group.
 */
export function requireMeta(tx: Tx): MetaRow {
  const meta = findMeta(tx);
  if (meta) return meta;
  if (findTombstone(tx)) refuse("group_purged", "This group was settled and has been removed.");
  refuse("no_group", "No such group.");
}

export function findMemberByProfile(tx: Tx, profileId: string): MemberRow | undefined {
  return tx.select().from(schema.members).where(eq(schema.members.profileId, profileId)).get();
}

/**
 * The caller's own member row, which is the only identity any write path gets.
 *
 * This is the whole of authorization in this object, and it is deliberately
 * the same three lines everywhere. Membership is the only question: there is
 * no owner, no admin and no rank, because the powers a role was gating turned
 * out to be either destructive enough that nobody should hold them over
 * somebody else, or harmless enough that everybody should.
 *
 * Note what is not a parameter: which member the caller *is*. Postgres had to
 * forbid that with a trigger on every write path, because `upsert_entry` could
 * otherwise have taken an author. Resolving it here means there is nothing to
 * forbid.
 */
export function requireActiveMember(tx: Tx, profileId: string): MemberRow {
  const member = tx
    .select()
    .from(schema.members)
    .where(and(eq(schema.members.profileId, profileId), isNull(schema.members.leftAt)))
    .get();

  if (!member) refuse("not_member", "You are not a member of this group.");
  return member;
}

export function requireMember(tx: Tx, memberId: string): MemberRow {
  const member = tx.select().from(schema.members).where(eq(schema.members.id, memberId)).get();
  if (!member) refuse("no_such_member", "No such member in this group.");
  return member;
}

/** An instant, in the one format everything here stores and sends. */
export function nowIso(at: number = Date.now()): string {
  return new Date(at).toISOString();
}
