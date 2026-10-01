import { eq, inArray } from "drizzle-orm";

import { chunked } from "../../chunked";
import * as schema from "../../db/group/schema";
import { type Entry, type EntryInput, editableEntryColumns } from "../../schemas/ledger";
import { appendSnapshot, byMember, moneyRows } from "./events";
import { refuse } from "./refusal";
import { type EntryRow, nextSeq, requireMeta, type Tx, type WriteContext } from "./store";
import { touchDormancy } from "./upkeep";

/**
 * The expense write path. Every rule is checked here against the finished
 * shape: the balance invariant, who may be named, staleness, and whether the
 * write changes anything at all.
 */

/** Entries with their payers and shares, in three queries. */
export function readEntries(tx: Tx, rows: EntryRow[]): Entry[] {
  if (rows.length === 0) return [];
  const children = chunked(rows.map((row) => row.id));
  const payers = Map.groupBy(
    children.flatMap((ids) => tx.select().from(schema.entryPayers).where(inArray(schema.entryPayers.entryId, ids)).all()),
    (row) => row.entryId,
  );
  const shares = Map.groupBy(
    children.flatMap((ids) => tx.select().from(schema.entryShares).where(inArray(schema.entryShares.entryId, ids)).all()),
    (row) => row.entryId,
  );

  return rows.map((row) => ({
    ...row,
    payers: (payers.get(row.id) ?? []).map(({ memberId, amountMinor }) => ({ memberId, amountMinor })),
    shares: (shares.get(row.id) ?? []).map(({ memberId, amountMinor, weightMicros }) => ({ memberId, amountMinor, weightMicros })),
  }));
}

function readEntry(tx: Tx, id: string): Entry | undefined {
  const row = tx.select().from(schema.entries).where(eq(schema.entries.id, id)).get();
  return row && readEntries(tx, [row])[0];
}

function requireEntry(tx: Tx, id: string): Entry {
  const entry = readEntry(tx, id);
  if (!entry) refuse("no_such_entry", "No such expense.");
  return entry;
}

/**
 * Records, edits, deletes or restores an expense, whole: an amount, its payers,
 * its shares and whether it counts are one fact.
 */
export function putEntry(tx: Tx, id: string, input: EntryInput, { now, actor }: WriteContext): Entry {
  const meta = requireMeta(tx);
  assertBalanced(input);
  assertMembersExist(tx, input);

  // The id is client-minted, so a retry after a lost response finds its own row here.
  const stored = readEntry(tx, id);
  if (stored) {
    assertBaseIsCurrent(stored, input);
    if (JSON.stringify(comparable(stored)) === JSON.stringify(comparable(input))) return stored;
  }

  const seq = nextSeq(tx);

  // A live expense brings an archived group back, silently: the expense is the record.
  if (meta.archivedAt !== null && input.deletedAt === null) {
    tx.update(schema.meta).set({ archivedAt: null, updatedAt: now, seq }).where(eq(schema.meta.id, meta.id)).run();
  }

  // A rate keeps its timestamp unless the rate or its source changed.
  const fxAt = stored && stored.fxRate === input.fxRate && stored.fxSource === input.fxSource ? stored.fxAt : input.fxRate !== null ? now : null;
  // The device says whether; the server's clock says when, once.
  const deletedAt = input.deletedAt === null ? null : (stored?.deletedAt ?? now);

  // Only the editable columns, by name: the object is called over RPC, not through the Zod schema.
  const fields = Object.fromEntries(editableEntryColumns.map((column) => [column, input[column]])) as Pick<EntryInput, (typeof editableEntryColumns)[number]>;
  const columns = { ...fields, fxAt, deletedAt, updatedAt: now, seq };

  // Authorship and creation time are never rewritten by an edit.
  tx.insert(schema.entries)
    .values({ id, createdBy: actor.id, createdAt: now, ...columns })
    .onConflictDoUpdate({ target: schema.entries.id, set: columns })
    .run();

  tx.delete(schema.entryPayers).where(eq(schema.entryPayers.entryId, id)).run();
  tx.delete(schema.entryShares).where(eq(schema.entryShares.entryId, id)).run();
  tx.insert(schema.entryPayers)
    .values(input.payers.map(({ memberId, amountMinor }) => ({ entryId: id, memberId, amountMinor })))
    .run();
  tx.insert(schema.entryShares)
    .values(input.shares.map(({ memberId, amountMinor, weightMicros }) => ({ entryId: id, memberId, amountMinor, weightMicros })))
    .run();

  const entry = requireEntry(tx, id);
  appendSnapshot(tx, entry, entry.payers, entry.shares, { seq, now, actorId: actor.id });
  touchDormancy(tx, now);
  return entry;
}

/** `sum(payers) = sum(shares) = amount`, which is what makes client-side splitting safe. */
function assertBalanced(input: EntryInput): void {
  const paid = input.payers.reduce((sum, payer) => sum + payer.amountMinor, 0);
  const owed = input.shares.reduce((sum, share) => sum + share.amountMinor, 0);
  if (paid !== input.amountMinor || owed !== input.amountMinor) {
    refuse("unbalanced", `This expense does not add up: ${input.amountMinor} recorded, ${paid} paid, ${owed} owed.`);
  }
}

function assertMembersExist(tx: Tx, input: EntryInput): void {
  if (new Set(input.payers.map((payer) => payer.memberId)).size !== input.payers.length) {
    refuse("malformed", "The same person is listed twice as a payer.");
  }
  if (new Set(input.shares.map((share) => share.memberId)).size !== input.shares.length) {
    refuse("malformed", "The same person is listed twice in the split.");
  }

  const named = [...new Set([...input.payers, ...input.shares].map((row) => row.memberId))];
  const known = chunked(named).flatMap((ids) => tx.select({ id: schema.members.id }).from(schema.members).where(inArray(schema.members.id, ids)).all());
  if (known.length !== named.length) refuse("no_such_member", "This expense names somebody who is not in this group.");
}

/**
 * A stale base is refused only when the write would move money; two people
 * fixing a typo never arbitrate. A null base claims no version.
 */
function assertBaseIsCurrent(stored: Entry, input: EntryInput): void {
  if (input.baseSeq === null || stored.seq === input.baseSeq) return;
  if (JSON.stringify(money(stored)) !== JSON.stringify(money(input))) {
    refuse("stale_base", "This expense changed since you opened it.");
  }
}

type Comparable = Omit<EntryInput, "baseSeq">;

/** What moves a balance. Deleting or restoring moves every payer and share at once. */
function money(entry: Comparable) {
  return { counts: entry.deletedAt === null, amountMinor: entry.amountMinor, payers: moneyRows(entry.payers), shares: moneyRows(entry.shares) };
}

/** Everything a save can change; an unchanged push spends no sequence number. */
function comparable(entry: Comparable) {
  return {
    columns: editableEntryColumns.map((column) => entry[column]),
    money: money(entry),
    weights: [...entry.shares].sort(byMember).map((share) => share.weightMicros),
  };
}
