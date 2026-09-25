import { eq, inArray } from "drizzle-orm";

import * as schema from "../../db/group/schema";
import type { Entry, EntryInput, Payer, Share } from "../../schemas/ledger";
import { appendSnapshot } from "./events";
import { refuse } from "./refusal";
import { type EntryRow, type MemberRow, nextSeq, requireMeta, type Tx } from "./store";

/**
 * The write path.
 *
 * Everything an expense has to satisfy is checked here, in one place, against
 * the finished shape: the balance invariant, who may be named, whether the
 * edit was composed against a version that has since moved, and whether it
 * changes anything at all. That is possible because there is one writer and it
 * sees the whole change before anybody else sees any of it.
 */

/** The shape a stale edit is judged against. Weights excluded on purpose. */
interface Money {
  amountMinor: number;
  payers: { memberId: string; amountMinor: number }[];
  shares: { memberId: string; amountMinor: number }[];
}

export interface WriteContext {
  now: string;
  actor: MemberRow;
}

export interface EntryWrite {
  entry: Entry;
  /** False when the push changed nothing and no sequence number was spent. */
  changed: boolean;
  /** Whether this write brought an archived group back to life. */
  unarchived: boolean;
}

export function readEntry(tx: Tx, row: EntryRow): Entry {
  const payers = tx.select({ memberId: schema.entryPayers.memberId, amountMinor: schema.entryPayers.amountMinor }).from(schema.entryPayers).where(eq(schema.entryPayers.entryId, row.id)).all();

  const shares = tx.select({ memberId: schema.entryShares.memberId, amountMinor: schema.entryShares.amountMinor, weightMicros: schema.entryShares.weightMicros }).from(schema.entryShares).where(eq(schema.entryShares.entryId, row.id)).all();

  return { ...row, payers, shares };
}

/**
 * A page of entries with their children, in three queries rather than 2n+1.
 *
 * Grouped through a `Map` rather than by filtering the child arrays per row.
 * That reads better and is the difference between linear and quadratic: a
 * 500-change page of four-way splits is four thousand child rows, and
 * filtering them once per entry is two million string comparisons against a
 * request budget of ten milliseconds of CPU.
 */
export function readEntries(tx: Tx, rows: EntryRow[]): Entry[] {
  if (rows.length === 0) return [];
  const ids = rows.map((row) => row.id);

  const payers = groupBy(tx.select().from(schema.entryPayers).where(inArray(schema.entryPayers.entryId, ids)).all(), (row) => row.entryId);
  const shares = groupBy(tx.select().from(schema.entryShares).where(inArray(schema.entryShares.entryId, ids)).all(), (row) => row.entryId);

  return rows.map((row) => ({
    ...row,
    payers: (payers.get(row.id) ?? []).map(({ memberId, amountMinor }) => ({ memberId, amountMinor })),
    shares: (shares.get(row.id) ?? []).map(({ memberId, amountMinor, weightMicros }) => ({ memberId, amountMinor, weightMicros })),
  }));
}

function groupBy<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const grouped = new Map<string, T[]>();
  for (const row of rows) {
    const bucket = grouped.get(key(row));
    if (bucket) bucket.push(row);
    else grouped.set(key(row), [row]);
  }
  return grouped;
}

/**
 * Records or edits an expense, whole.
 *
 * Whole, and not by column, because an amount, its payers and its shares are
 * one coherent fact rather than a bag of independently mergeable fields.
 * Merging them pairwise is how you get a row that balances arithmetically and
 * describes something nobody asked for.
 */
export function upsertEntry(tx: Tx, input: EntryInput, context: WriteContext): EntryWrite {
  const meta = requireMeta(tx);

  assertBalanced(input);
  assertMembersExist(tx, input);

  const existing = tx.select().from(schema.entries).where(eq(schema.entries.id, input.id)).get();

  /**
   * A retry that re-minted the id.
   *
   * The client mints both the entry id and the client key and reuses both on
   * retry, so this is not the ordinary path — `on conflict (id)` is. But a key
   * that already names an expense here, on an id that does not, can only be a
   * push whose response was lost, and answering with the expense it already
   * recorded is the whole point of the key existing. Refusing it instead — on
   * a uniqueness constraint, say — wedges the device's outbox on a write the
   * server has already accepted.
   */
  if (!existing && input.clientKey !== null) {
    const byKey = tx.select().from(schema.entries).where(eq(schema.entries.clientKey, input.clientKey)).get();
    if (byKey) return { entry: readEntry(tx, byKey), changed: false, unarchived: false };
  }

  if (existing) {
    // Read once and hand it to both checks. Each of them needs the whole
    // stored shape, and reading it twice is two more queries on the hottest
    // path in the application.
    const stored = readEntry(tx, existing);

    assertBaseIsCurrent(stored, input);
    if (!differs(stored, input)) {
      return { entry: stored, changed: false, unarchived: false };
    }
  }

  const seq = nextSeq(tx);

  /**
   * A group somebody is still using is not dormant, whatever the alarm decided
   * three months ago. Archiving is reversible precisely so that being wrong
   * about it costs nothing, and this is the line that makes it so: adding an
   * expense brings the group back by itself, with nothing for anybody to find
   * or undo.
   *
   * Deliberately no `group_restored` event. Recording this as "Ravi restored
   * the group" when Ravi added a dinner puts a false sentence in the one place
   * whose whole value is being true — and the revival is not lost by going
   * unrecorded, because the expense that caused it is one line further down
   * with the same actor and the same timestamp. Straight-line code knows which
   * of the two it is doing; anything that has to infer it after the fact does
   * not.
   */
  const unarchived = meta.archivedAt !== null;
  if (unarchived) {
    tx.update(schema.meta).set({ archivedAt: null, updatedAt: context.now, seq }).where(eq(schema.meta.id, meta.id)).run();
  }

  /**
   * When the rate was taken. Unchanged if the rate and its source are, because
   * a snapshot that did not move did not get taken again.
   */
  const fxAt = existing && existing.fxRate === input.fxRate && existing.fxSource === input.fxSource ? existing.fxAt : input.fxRate !== null ? context.now : null;

  const columns = {
    kind: input.kind,
    description: input.description,
    categoryId: input.categoryId,
    currency: input.currency,
    amountMinor: input.amountMinor,
    entryDate: input.entryDate,
    splitKind: input.splitKind,
    fxRate: input.fxRate,
    fxSource: input.fxSource,
    fxAt,
    notes: input.notes,
    updatedAt: context.now,
    seq,
  };

  /**
   * `createdBy`, `createdAt`, `clientKey` and `deletedAt` are in the insert and
   * not in the update, which is the whole of what `guard_entry_write` used to
   * do. Who recorded an expense and when cannot be rewritten because there is
   * no statement that rewrites them; a saved edit does not resurrect a deleted
   * expense because this does not touch `deletedAt`. A rule expressed as an
   * absent assignment cannot be got around by a caller, which is more than the
   * trigger could say — it was reachable only for callers with a JWT.
   */
  tx.insert(schema.entries)
    .values({
      id: input.id,
      createdBy: context.actor.id,
      clientKey: input.clientKey,
      createdAt: context.now,
      ...columns,
    })
    .onConflictDoUpdate({ target: schema.entries.id, set: columns })
    .run();

  replaceChildren(tx, input);

  const row = tx.select().from(schema.entries).where(eq(schema.entries.id, input.id)).get();
  if (!row) refuse("no_such_entry", "The entry vanished mid-write.");

  appendSnapshot(tx, row, input.payers, input.shares, { seq, now: context.now, actorId: context.actor.id });

  return { entry: readEntry(tx, row), changed: true, unarchived };
}

/**
 * Soft delete, always.
 *
 * A hard delete would vanish from the change feed, leaving the expense on
 * every device that had already synced it with no way to learn it went — and
 * taking the record of it with it. There is no method here that removes an
 * entry row, which is the same guarantee the missing DELETE policy used to
 * give, stated as an absence rather than a permission.
 */
export function deleteEntry(tx: Tx, entryId: string, baseSeq: number, context: WriteContext): EntryWrite {
  return setDeleted(tx, entryId, baseSeq, context, true);
}

/**
 * Putting one back.
 *
 * The activity feed has always had a word for this and no way to reach it:
 * `upsert_entry` never touched `deleted_at`, and direct DML was closed, so
 * `restored` was a kind the client could render and the server could not
 * produce. Soft deletion without an undo is just deletion with extra steps.
 */
export function restoreEntry(tx: Tx, entryId: string, baseSeq: number, context: WriteContext): EntryWrite {
  return setDeleted(tx, entryId, baseSeq, context, false);
}

function setDeleted(tx: Tx, entryId: string, baseSeq: number, context: WriteContext, deleted: boolean): EntryWrite {
  requireMeta(tx);

  const existing = tx.select().from(schema.entries).where(eq(schema.entries.id, entryId)).get();

  /**
   * Deliberately the same answer whether the entry does not exist or belongs
   * to a group the caller cannot see — except that here it cannot belong to
   * another group at all, because this object holds one group's rows and an id
   * from elsewhere simply names nothing.
   */
  if (!existing) refuse("no_such_entry", "No such expense.");

  /**
   * A retry after the server committed but before its response arrived. The
   * row is already in the state being asked for, so hand back its current
   * version even though the caller still carries the older base.
   */
  if ((existing.deletedAt !== null) === deleted) {
    return { entry: readEntry(tx, existing), changed: false, unarchived: false };
  }

  /**
   * Unlike a prose-only edit, this always moves money: every payer and share
   * enters or leaves the live balance. So it must be composed against the
   * exact version the device last saw, and a missing base is a refusal rather
   * than a licence.
   */
  if (existing.seq !== baseSeq) {
    refuse("stale_base", "This expense changed since you opened it.");
  }

  const seq = nextSeq(tx);
  tx.update(schema.entries)
    .set({ deletedAt: deleted ? context.now : null, updatedAt: context.now, seq })
    .where(eq(schema.entries.id, entryId))
    .run();

  const row = tx.select().from(schema.entries).where(eq(schema.entries.id, entryId)).get();
  if (!row) refuse("no_such_entry", "The entry vanished mid-write.");

  const entry = readEntry(tx, row);
  appendSnapshot(tx, row, entry.payers, entry.shares, { seq, now: context.now, actorId: context.actor.id });

  return { entry, changed: true, unarchived: false };
}

/**
 * `sum(payers) = sum(shares) = amount`.
 *
 * One function, called once, with the finished shape in hand — which is the
 * only way to check it. An expense and its payers and shares are three tables;
 * anything that validates them as they arrive has to be deferred to the end of
 * the change anyway, and has to fire on all three, or an amount edited alone,
 * or an expense saved with no children at all, slips past.
 *
 * It catches every rounding bug, every bad largest-remainder implementation
 * and every partial write, and it is what makes it safe for the client to
 * compute splits at all.
 */
function assertBalanced(input: EntryInput): void {
  const paid = input.payers.reduce((sum, payer) => sum + payer.amountMinor, 0);
  const owed = input.shares.reduce((sum, share) => sum + share.amountMinor, 0);

  if (paid !== input.amountMinor || owed !== input.amountMinor) {
    refuse("unbalanced", `This expense does not add up: ${input.amountMinor} recorded, ${paid} paid, ${owed} owed.`);
  }
}

/**
 * Everybody named is somebody here, once.
 *
 * "Is this member in this group" is an existence test and nothing more: this
 * object holds one group's members and no others, so "in this group" and "in
 * this table" are the same statement.
 *
 * The duplicate check is new, and it is not theoretical: two payer rows for
 * one member collide on the primary key, which would surface as a constraint
 * error from deep inside a transaction rather than as something a client can
 * read.
 */
function assertMembersExist(tx: Tx, input: EntryInput): void {
  if (new Set(input.payers.map((payer) => payer.memberId)).size !== input.payers.length) {
    refuse("malformed", "The same person is listed twice as a payer.");
  }
  if (new Set(input.shares.map((share) => share.memberId)).size !== input.shares.length) {
    refuse("malformed", "The same person is listed twice in the split.");
  }

  const named = [...new Set([...input.payers, ...input.shares].map((row) => row.memberId))];
  const known = tx.select({ id: schema.members.id }).from(schema.members).where(inArray(schema.members.id, named)).all();

  if (known.length !== named.length) {
    refuse("no_such_member", "This expense names somebody who is not in this group.");
  }
}

/**
 * Refuses a stale edit, but only one that would move money.
 *
 * A stale base alone is not a conflict worth refusing: two people fixing a
 * typo should not have to arbitrate, and last-write-wins on prose costs
 * nobody anything. What cannot pass silently is a write that would move money
 * away from where the server currently has it — and because this writes the
 * whole entry, that includes an edit which changes only the description while
 * carrying a stale amount along with it. Comparing the money rather than the
 * parameters catches exactly that and lets the harmless cases through.
 *
 * A null base means "I am not claiming one" — a row this device invented, or a
 * client that does not send one — and skips the check, which is why the
 * parameter could be added without changing any existing behaviour.
 */
function assertBaseIsCurrent(stored: Entry, input: EntryInput): void {
  if (input.baseSeq === null || stored.seq === input.baseSeq) return;

  if (JSON.stringify(moneyOf(stored)) !== JSON.stringify(moneyOf(input))) {
    refuse("stale_base", "This expense changed since you opened it.");
  }
}

function moneyOf(money: Money): Money {
  return {
    amountMinor: money.amountMinor,
    payers: [...money.payers].sort(byMember).map(({ memberId, amountMinor }) => ({ memberId, amountMinor })),
    shares: [...money.shares].sort(byMember).map(({ memberId, amountMinor }) => ({ memberId, amountMinor })),
  };
}

function byMember(a: { memberId: string }, b: { memberId: string }): number {
  return a.memberId < b.memberId ? -1 : a.memberId > b.memberId ? 1 : 0;
}

/**
 * Whether this push would change anything at all.
 *
 * A push that changes nothing spends no sequence number, which is what keeps a
 * retried outbox item from re-notifying every device in the group on every
 * attempt. Writing unconditionally and deduplicating the *event* afterwards
 * keeps the activity feed clean and still sends the row to every phone in the
 * group for no reason.
 */
function differs(stored: Entry, input: EntryInput): boolean {
  return JSON.stringify(comparable(stored)) !== JSON.stringify(comparable(input));
}

/**
 * Everything a save can change, in a fixed order.
 *
 * One function over both shapes rather than two parallel object literals, so
 * a field added to `EntryInput` and forgotten here is a type error instead of
 * a change that silently stops travelling.
 */
function comparable(entry: Comparable) {
  return {
    kind: entry.kind,
    description: entry.description,
    categoryId: entry.categoryId,
    currency: entry.currency,
    entryDate: entry.entryDate,
    splitKind: entry.splitKind,
    fxRate: entry.fxRate,
    fxSource: entry.fxSource,
    notes: entry.notes,
    money: moneyOf(entry),
    weights: [...entry.shares].sort(byMember).map((share) => share.weightMicros),
  };
}

type Comparable = Omit<EntryInput, "id" | "clientKey" | "baseSeq">;

/**
 * Replaced wholesale rather than diffed, matching what the client does, so the
 * two cannot disagree about what an edit means.
 */
function replaceChildren(tx: Tx, input: EntryInput): void {
  tx.delete(schema.entryPayers).where(eq(schema.entryPayers.entryId, input.id)).run();
  tx.delete(schema.entryShares).where(eq(schema.entryShares.entryId, input.id)).run();

  tx.insert(schema.entryPayers)
    .values(input.payers.map((payer: Payer) => ({ entryId: input.id, memberId: payer.memberId, amountMinor: payer.amountMinor })))
    .run();

  tx.insert(schema.entryShares)
    .values(input.shares.map((share: Share) => ({ entryId: input.id, memberId: share.memberId, amountMinor: share.amountMinor, weightMicros: share.weightMicros })))
    .run();
}
