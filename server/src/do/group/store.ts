import { and, eq, isNotNull, isNull, sql } from "drizzle-orm";
import type { DrizzleSqliteDODatabase } from "drizzle-orm/durable-sqlite";

import * as schema from "../../db/group/schema";
import { refuse } from "./refusal";

export type GroupDb = DrizzleSqliteDODatabase<typeof schema>;

/** Every query runs in a `transactionSync`, reads included, so helpers have one signature. */
export type Tx = Parameters<Parameters<GroupDb["transaction"]>[0]>[0];

export type MetaRow = typeof schema.meta.$inferSelect;
export type MemberRow = typeof schema.members.$inferSelect;
export type EntryRow = typeof schema.entries.$inferSelect;

/** A write's clock and its author, who is always the caller's own member row. */
export interface WriteContext {
  now: string;
  actor: MemberRow;
}

/** The next sequence number, allocated in the same transaction as the rows it stamps. */
export function nextSeq(tx: Tx): number {
  const row = tx.get<{ value: number }>(
    sql`insert into ${schema.counter} (name, value) values ('seq', 1)
        on conflict(name) do update set value = ${schema.counter.value} + 1
        returning value`,
  );
  return row.value;
}

export function currentSeq(tx: Tx): number {
  return tx.select({ value: schema.counter.value }).from(schema.counter).where(eq(schema.counter.name, "seq")).get()?.value ?? 0;
}

export function findMeta(tx: Tx): MetaRow | undefined {
  return tx.select().from(schema.meta).get();
}

export function findTombstone(tx: Tx) {
  return tx.select().from(schema.tombstone).get();
}

/** The group, or a refusal saying which kind of nothing is here. */
export function requireMeta(tx: Tx): MetaRow {
  const meta = findMeta(tx);
  if (meta) return meta;
  if (findTombstone(tx)) refuse("group_purged", "This group was settled and has been removed.");
  refuse("no_group", "No such group.");
}

export function findMemberByProfile(tx: Tx, profileId: string): MemberRow | undefined {
  return tx.select().from(schema.members).where(eq(schema.members.profileId, profileId)).get();
}

/** The caller's own current member row: the whole of authorization here. */
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

/** Whether anybody here could still read this group. */
export function hasAccountHolders(tx: Tx): boolean {
  return tx.select({ id: schema.members.id }).from(schema.members).where(isNotNull(schema.members.profileId)).limit(1).get() !== undefined;
}

/** Deletes the whole group, children first, leaving a tombstone for the feed. */
export function purge(tx: Tx, now: string): void {
  const seq = nextSeq(tx);
  const groupId = requireMeta(tx).id;

  tx.delete(schema.entryPayers).run();
  tx.delete(schema.entryShares).run();
  tx.delete(schema.entries).run();
  tx.delete(schema.events).run();
  tx.delete(schema.invites).run();
  tx.delete(schema.groupLink).run();
  tx.delete(schema.meta).run();
  tx.delete(schema.members).run();

  tx.insert(schema.tombstone).values({ id: "purged", groupId, purgedAt: now, seq }).onConflictDoNothing().run();
}

export function nowIso(at: number = Date.now()): string {
  return new Date(at).toISOString();
}
