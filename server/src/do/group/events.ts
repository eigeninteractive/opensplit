import { and, desc, eq, sql } from "drizzle-orm";
import type { GroupEventKind, LinkEventKind, MemberEventKind } from "../../db/group/schema";
import * as schema from "../../db/group/schema";
import type { EntrySnapshot, GroupEventPayload, LinkEventPayload, MemberEventPayload, MoneyRow } from "../../schemas/ledger";
import type { EntryRow, Tx } from "./store";

/**
 * The activity record, derived by the object from what it committed, so a
 * client cannot describe its own edit. An expense is an after-image (the
 * device diffs consecutive snapshots); everything else is a named event.
 */

interface Written {
  seq: number;
  now: string;
  actorId: string | null;
}

/** A kind paired with its payload column, so a mismatch does not compile. */
type Append = Written & ({ kind: "entry"; subjectId: string; entry: EntrySnapshot } | { kind: MemberEventKind; subjectId: string; member: MemberEventPayload } | { kind: GroupEventKind; group: GroupEventPayload } | { kind: LinkEventKind; subjectId: string; link: LinkEventPayload });

export function append(tx: Tx, event: Append): void {
  const { seq, now, actorId, kind, ...payload } = event;
  const ordinal = tx.select({ count: sql<number>`count(*)` }).from(schema.events).where(eq(schema.events.seq, seq)).get()?.count ?? 0;

  tx.insert(schema.events)
    .values({ id: crypto.randomUUID(), actorId, createdAt: now, kind, seq, ordinal, ...payload })
    .run();
}

export function byMember(a: { memberId: string }, b: { memberId: string }): number {
  return a.memberId < b.memberId ? -1 : a.memberId > b.memberId ? 1 : 0;
}

/** Payers or shares reduced to member and amount, in a stable order. */
export function moneyRows(rows: readonly MoneyRow[]): MoneyRow[] {
  return [...rows].sort(byMember).map(({ memberId, amountMinor }) => ({ memberId, amountMinor }));
}

/** Built in one place so two snapshots of an unchanged expense compare equal as JSON. */
export function snapshotOf(entry: EntryRow, payers: readonly MoneyRow[], shares: readonly MoneyRow[]): EntrySnapshot {
  return {
    kind: entry.kind,
    description: entry.description,
    currency: entry.currency,
    amountMinor: entry.amountMinor,
    entryDate: entry.entryDate,
    splitKind: entry.splitKind,
    categoryId: entry.categoryId,
    notes: entry.notes,
    deletedAt: entry.deletedAt,
    payers: moneyRows(payers),
    shares: moneyRows(shares),
  };
}

/** Appends a snapshot unless the latest one already says the same. */
export function appendSnapshot(tx: Tx, entry: EntryRow, payers: readonly MoneyRow[], shares: readonly MoneyRow[], context: Written): void {
  const snapshot = snapshotOf(entry, payers, shares);
  const previous = tx
    .select({ entry: schema.events.entry })
    .from(schema.events)
    .where(and(eq(schema.events.subjectId, entry.id), eq(schema.events.kind, "entry")))
    .orderBy(desc(schema.events.seq))
    .limit(1)
    .get();

  if (previous && JSON.stringify(previous.entry) === JSON.stringify(snapshot)) return;
  append(tx, { ...context, kind: "entry", subjectId: entry.id, entry: snapshot });
}
