import { and, desc, eq, sql } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { EntrySnapshot, GroupEventPayload, LinkEventPayload, MemberEventPayload } from "../../schemas/ledger";
import type { EntryRow, Tx } from "./store";

/**
 * The record, written by the thing that committed the change.
 *
 * Why the server writes it rather than the client: a device that authors its
 * own history can describe a ₹400 → ₹4,000 edit as a ten-rupee correction, and
 * nothing on the server can tell. Worse, it can rewrite only the shares —
 * moving a hundred rupees from itself to a flatmate while the total stays put,
 * which the balance invariant happily accepts — and append no history at all.
 * Deriving the record here removes the claim from the wire: the client no
 * longer asserts what changed, it renders what the server observed.
 *
 * Why expenses are after-images and everything else is a named event: in
 * Postgres this was forced. One logical change to an expense spanned three
 * tables, so the only coherent moment to look was COMMIT, by which point the
 * before-image was gone. That constraint is gone here — `upsertEntry` holds
 * both images in local variables — but the shape it produced turns out to be
 * the right one anyway, for a reason that has nothing to do with triggers:
 *
 *   an expense line has to read "Ravi's share, from ₹200 to ₹300", which is a
 *   field-level diff. A chain of after-images yields that for free and covers
 *   any field added later without being taught about it. A named event would
 *   have to enumerate what changed and would silently omit whatever it had not
 *   been told about.
 *
 * Nothing below has that problem. "Priya joined" has no field-level diff worth
 * rendering — the kind *is* the information — so a snapshot chain would buy
 * nothing and cost a pairing step on every read. Which is the rule for
 * anything added here later: does this need a field-level diff? Snapshot.
 * Otherwise, an event.
 *
 * Still not event sourcing. Nothing is ever rebuilt from these rows. Balances
 * read `entries` and only `entries`, so a bug anywhere in this file can make
 * the feed wrong and can never make a balance wrong.
 */

interface Written {
  seq: number;
  now: string;
  /** Null when nobody can be named, which for a join is the ordinary case. */
  actorId: string | null;
}

/**
 * A kind and its payload, paired by the type system.
 *
 * This is where "the payload depends on the kind" stops being a comment. There
 * are four shapes, the set is closed, and the discriminated union means a
 * `member_renamed` carrying a group's payload does not compile — which is a
 * better guarantee than any runtime check, because the record is written from
 * about ten call sites and read by a client that parses it per kind.
 *
 * `subjectId` is part of the discrimination too: it is the entry, member or
 * token an event is about, and it is null exactly for the kinds whose subject
 * is the group itself, which `meta` already names.
 */
type Append = Written &
  (
    | { kind: "entry"; subjectId: string; payload: EntrySnapshot }
    | { kind: "member_added" | "member_joined" | "member_left" | "member_renamed"; subjectId: string; payload: MemberEventPayload }
    | { kind: "group_renamed" | "group_archived" | "group_restored"; subjectId?: null; payload: GroupEventPayload }
    | { kind: "link_created" | "link_revoked"; subjectId: string; payload: LinkEventPayload }
  );

export function append(tx: Tx, event: Append): void {
  // Where this line falls among the lines this same change wrote. Counted
  // rather than passed in, so a caller appending two events cannot forget.
  const written = tx.select({ count: sql<number>`count(*)` }).from(schema.events).where(eq(schema.events.seq, event.seq)).get();

  tx.insert(schema.events)
    .values({
      ordinal: written?.count ?? 0,
      id: crypto.randomUUID(),
      actorId: event.actorId,
      createdAt: event.now,
      kind: event.kind,
      subjectId: event.subjectId ?? null,
      payload: event.payload,
      seq: event.seq,
    })
    .run();
}

/**
 * What an expense looked like after a change.
 *
 * Built in exactly one place so that two snapshots of an unchanged expense
 * compare equal as strings: the key order is this function's insertion order,
 * and the only way to add a field is to add it here, where it is compared by
 * construction.
 *
 * `fxRate`, `fxSource` and `fxAt` are absent on purpose — they move whenever
 * the currency does and would make every currency edit read as two changes.
 * `updatedAt` and `seq` are absent because they move on every write by
 * definition, which would make a save that altered nothing read as an edit.
 */
export function snapshotOf(entry: EntryRow, payers: { memberId: string; amountMinor: number }[], shares: { memberId: string; amountMinor: number }[]): EntrySnapshot {
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
    payers: [...payers].sort(byMember).map((p) => ({ memberId: p.memberId, amountMinor: p.amountMinor })),
    shares: [...shares].sort(byMember).map((s) => ({ memberId: s.memberId, amountMinor: s.amountMinor })),
  };
}

function byMember(a: { memberId: string }, b: { memberId: string }): number {
  return a.memberId < b.memberId ? -1 : a.memberId > b.memberId ? 1 : 0;
}

/**
 * Appends a snapshot, unless it is already what the newest one says.
 *
 * The five-events-for-one-save problem this used to solve is gone: a save is
 * one call inside one transaction and writes one event, rather than firing a
 * deferred trigger once per affected row across three tables. What is left is
 * the smaller and still-real case — a re-saved editor, or a push retried after
 * the response was lost — where nothing this record describes has moved and a
 * feed full of "Ravi edited nothing" is worse than no feed.
 *
 * Returns whether anything was written, which the caller uses to decide
 * whether the change is worth waking a phone for.
 */
export function appendSnapshot(tx: Tx, entry: EntryRow, payers: { memberId: string; amountMinor: number }[], shares: { memberId: string; amountMinor: number }[], context: { seq: number; now: string; actorId: string }): boolean {
  const payload = snapshotOf(entry, payers, shares);

  const previous = tx
    .select({ payload: schema.events.payload })
    .from(schema.events)
    .where(and(eq(schema.events.subjectId, entry.id), eq(schema.events.kind, "entry")))
    .orderBy(desc(schema.events.seq))
    .limit(1)
    .get();

  if (previous && JSON.stringify(previous.payload) === JSON.stringify(payload)) {
    return false;
  }

  append(tx, { ...context, kind: "entry", subjectId: entry.id, payload });
  return true;
}
