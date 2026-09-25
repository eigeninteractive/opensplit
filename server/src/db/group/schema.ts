import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, real, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

import type { EventPayload } from "../../schemas/ledger";

/** The closed vocabularies stored here. `schemas/ledger.ts` puts these same lists on the wire. */
export const entryKinds = ["expense", "settlement"] as const;
export const splitKinds = ["equal", "exact", "shares", "percent"] as const;
export const eventKinds = ["entry", "member_added", "member_joined", "member_left", "member_renamed", "group_renamed", "group_archived", "group_restored", "link_created", "link_revoked"] as const;

/** What each kind of staged D1 write carries. See `outbox` below. */
export type MembershipWrite = { groupId: string; profileId: string; leftAt: string | null; updatedAt: string };
export type LinkTokenWrite = { groupId: string; token: string; tokenKind: "invite" | "group_link"; revoked: boolean };
export type PurgeWrite = { groupId: string };
export type OutboxPayload = MembershipWrite | LinkTokenWrite | PurgeWrite;

/**
 * One group's ledger, inside one Durable Object.
 *
 * The largest thing to notice here is a column that is missing from every
 * table: `group_id`. A Durable Object *is* the group, so the scope is the
 * address of the database rather than a column on six tables and a predicate
 * on every query that touches them.
 *
 * That is not tidiness. Three rules stop needing to be written down at all,
 * because they are only expressible as rules when the scope is data:
 *
 *   - "an entry cannot be moved into another group" — there is no column to
 *     move it with, and an id from another group simply names nothing here;
 *   - "a share cannot name a member of a different group" — the members table
 *     holds this group's members and no others, so the check is existence;
 *   - "a member cannot carry themselves into another group" — same.
 *
 * None of those has a guard in this codebase, and the absence is the point.
 *
 * Timestamps are ISO-8601 UTC strings, matching D1 and the wire. One
 * canonical rendering, stored and sent — which matters most for the activity
 * snapshots, where a timestamp that renders differently on a re-read makes a
 * re-save look like an edit.
 *
 * The CHECK constraints are honest about what they are. Nothing but the code
 * in `src/do/group/` can reach these tables — there is no query interface, no
 * direct DML, no second door — so a constraint here is not a security
 * boundary. It is an assertion that catches *our* bugs at the write that
 * caused them, which is worth having and costs nothing.
 */

/**
 * The sequence allocator, and the reason the sync protocol got simpler.
 *
 * A Durable Object has exactly one writer, so it can hand out a strictly
 * increasing integer. That is one cursor per group instead of a keyset cursor
 * per feed, and it closes the class of bug where a row bumped mid-sweep moves
 * past a cursor that has already read it.
 *
 * One seq per committed change, not per row. A save that writes an entry, four
 * shares and an event stamps all of them with the same number, so a client
 * cursor either sees that whole change or none of it. Paging can never tear a
 * write in half, which a per-row counter would allow.
 */
export const counter = sqliteTable("counter", {
  name: text("name").primaryKey(),
  value: integer("value").notNull(),
});

/**
 * A member: group-scoped, and possibly nobody's account.
 *
 * `profileId is null` is a placeholder — a real person, added by a friend, who
 * can pay, hold a balance and be settled with before they have ever heard of
 * this app. Claiming an invite sets exactly that one column, which is why
 * joining a group rewrites no financial row and moves no balance.
 */
export const members = sqliteTable(
  "members",
  {
    id: text("id").primaryKey(),

    /** Null means a placeholder. This is the column an invite claim sets. */
    profileId: text("profile_id"),

    displayName: text("display_name").notNull(),

    /**
     * A payment handle for this person *in this group*.
     *
     * Group-scoped rather than only on the profile, because a placeholder has
     * no profile and settling up with a placeholder is exactly when the handle
     * is needed. Falls back to the linked profile's when null.
     *
     * The format is checked by Zod at the edge rather than by a CHECK here:
     * SQLite has no regular expressions, and `GLOB` cannot express the rule.
     * One regex in `schemas/` is better than an approximation in two places.
     */
    upiVpa: text("upi_vpa"),

    joinedAt: text("joined_at").notNull(),

    /**
     * Members are never deleted; they leave. Somebody who has paid for
     * anything must stay referenceable or their entries stop making sense.
     */
    leftAt: text("left_at"),

    updatedAt: text("updated_at").notNull(),
    seq: integer("seq").notNull(),
  },
  (table) => [
    /**
     * One account, one place.
     *
     * SQLite treats NULLs as distinct in a unique index, so any number of
     * placeholders coexist while a single profile can never hold two member
     * rows — which would be two balances for one human that can never be
     * reconciled. Exactly what `unique (group_id, profile_id)` bought, minus
     * the column.
     */
    uniqueIndex("members_profile").on(table.profileId),
    index("members_seq").on(table.seq),
    check("members_name_not_blank", sql`length(trim(${table.displayName})) > 0`),
  ],
);

/**
 * The group itself: one row, in a table named for what it is.
 *
 * `createdBy` is a **member** id, and it is a description rather than a
 * permission. Nothing reads it to decide anything.
 *
 * That distinction is the whole reason it is safe. A creator column becomes an
 * authorization the moment it stands in for membership — which is tempting,
 * because there is otherwise a window between a group existing and its
 * creator's member row landing — and a column that is an authorization is a
 * column somebody writes themselves into. Creating a group is one call that
 * writes both rows, so there is no window and no temptation.
 *
 * It also survives account deletion for free. The member row is demoted to a
 * placeholder and keeps its name, so "Ravi made this group" stays true when
 * Ravi's account is gone.
 */
export const meta = sqliteTable(
  "meta",
  {
    /** The group id, which is also this Durable Object's name. */
    id: text("id").primaryKey(),

    name: text("name").notNull(),
    defaultCurrency: text("default_currency").notNull(),

    /**
     * A 1:1 "direct" split is a two-member group with this set. There is
     * deliberately no second system for friends, which would duplicate the
     * entire balance and settlement path.
     */
    isDirect: integer("is_direct", { mode: "boolean" }).notNull().default(false),
    simplifyDebts: integer("simplify_debts", { mode: "boolean" }).notNull().default(true),

    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),
    createdAt: text("created_at").notNull(),

    /** Set by the dormancy alarm, or by somebody deliberately. Reversible. */
    archivedAt: text("archived_at"),

    /**
     * Descriptive, and no longer load-bearing.
     *
     * This column used to be the sync clock, which made it security-critical:
     * a client that could write it could backdate a change behind everybody's
     * cursor, or stamp one far enough ahead to pin every device's cursor there
     * and stop the group syncing permanently. Both were reachable, and both
     * took a trigger to close. `seq` is the cursor now, so this is just "when
     * was this last touched" — still written by the server, because there is
     * no reason to hand it over, but nothing depends on it being true.
     */
    updatedAt: text("updated_at").notNull(),
    seq: integer("seq").notNull(),
  },
  (table) => [check("meta_name_not_blank", sql`length(trim(${table.name})) > 0`)],
);

/**
 * What is left when a group is collected.
 *
 * Archived, a year silent and settled, a group is deleted — `meta`, the
 * members, the ledger and the record all go, which is the one operation here
 * that destroys somebody's data. This row is what stays: the fact that it
 * happened and the sequence number it happened at.
 *
 * A separate table rather than a column on `meta`, because `meta` is one of
 * the things being deleted. That is the point — a tombstone that carried the
 * group's name and who made it would be retaining exactly what was supposed
 * to go.
 *
 * It exists so the end of a group is something a device is *told*. Deleting
 * the rows and saying nothing leaves a phone that had synced the group holding
 * it forever, with no way to learn it went — and "the server does not have
 * this" cannot be read as "delete it", because that is also what a permissions
 * problem looks like. A feed cursored on a sequence number can carry the news,
 * so it does.
 */
export const tombstone = sqliteTable("tombstone", {
  /** Always `'purged'`. There is one of these, or there is none. */
  id: text("id").primaryKey(),

  /**
   * The group's own id, kept because `meta` is one of the things deleted.
   *
   * It is not personal data — it is the address the caller already used to
   * get here — and without it a collected group cannot name itself in the one
   * response it still gives.
   */
  groupId: text("group_id").notNull(),

  purgedAt: text("purged_at").notNull(),
  seq: integer("seq").notNull(),
});

/**
 * The ledger.
 *
 * Two shapes matter. `entry_payers` is a table, not a `paid_by` column,
 * because multiple payers on one bill is ordinary ("I got the food, you got
 * the drinks") and is where every simple clone falls over. `entry_shares`
 * stores both the resolved amount and the weight that produced it: only the
 * rule means a future rounding fix retroactively moves settled money, only the
 * amount means the split cannot be re-edited as "2:1:1".
 */
export const entries = sqliteTable(
  "entries",
  {
    id: text("id").primaryKey(),

    /**
     * A settlement is an entry, not a separate table: one payer, one share,
     * folding through the identical balance path and cancelling exactly the
     * debt the expenses created.
     */
    kind: text("kind", { enum: entryKinds }).notNull().default("expense"),

    description: text("description").notNull().default(""),
    categoryId: text("category_id"),

    /** What the money was actually spent in. Never converted on write. */
    currency: text("currency").notNull(),
    amountMinor: integer("amount_minor").notNull(),

    /** A calendar date, `YYYY-MM-DD`, not an instant. */
    entryDate: text("entry_date").notNull(),

    splitKind: text("split_kind", { enum: splitKinds }).notNull().default("equal"),

    /**
     * A display-only snapshot of the rate to the group's default currency as
     * it stood on `entryDate`. Never re-fetched: what a rupee was worth on the
     * night of the dinner is a fact about the transaction, not a live quote.
     *
     * `real`, because the value is a double on the wire, a double in Drift
     * and a double in the Dart model. Storing more precision than any reader
     * can hold would be ceremony — and it never enters a balance, which is
     * the one place a double would be unacceptable.
     */
    fxRate: real("fx_rate"),
    fxSource: text("fx_source"),
    fxAt: text("fx_at"),

    notes: text("notes"),

    /**
     * A member id, not a profile id: authorship belongs to the group-scoped
     * identity, so a placeholder's expenses survive them claiming an account.
     *
     * There is deliberately no parameter for this on any write path. The
     * Durable Object resolves the caller's own member row.
     */
    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),

    /**
     * Client-generated, so a retried push after a dropped connection is
     * idempotent rather than a second expense.
     */
    clientKey: text("client_key"),

    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),

    /**
     * Soft delete, always. A hard delete would vanish from the change feed and
     * strand the row on every device that had already synced it.
     */
    deletedAt: text("deleted_at"),

    seq: integer("seq").notNull(),
  },
  (table) => [
    index("entries_seq").on(table.seq),
    uniqueIndex("entries_client_key").on(table.clientKey),
    check("entries_amount_positive", sql`${table.amountMinor} > 0`),
    check("entries_fx_rate_positive", sql`${table.fxRate} is null or ${table.fxRate} > 0`),

    /**
     * Provenance without a rate cannot be audited and a rate without
     * provenance cannot be traced, so the three travel together or not at all.
     */
    check("entries_fx_complete", sql`(${table.fxRate} is null) = (${table.fxSource} is null) and (${table.fxRate} is null) = (${table.fxAt} is null)`),
  ],
);

/**
 * Money actually put down, by member.
 *
 * No `seq` of its own: payers are part of the entry and travel with it, which
 * is also what the wire format assumes. A change to a share is a change to the
 * entry, and stamping the entry is what makes it reach other devices.
 */
export const entryPayers = sqliteTable(
  "entry_payers",
  {
    entryId: text("entry_id")
      .notNull()
      .references(() => entries.id),
    memberId: text("member_id")
      .notNull()
      .references(() => members.id),
    amountMinor: integer("amount_minor").notNull(),
  },
  (table) => [primaryKey({ columns: [table.entryId, table.memberId] }), check("entry_payers_amount_positive", sql`${table.amountMinor} > 0`)],
);

export const entryShares = sqliteTable(
  "entry_shares",
  {
    entryId: text("entry_id")
      .notNull()
      .references(() => entries.id),
    memberId: text("member_id")
      .notNull()
      .references(() => members.id),

    /**
     * Zero is legitimate — somebody present who owes nothing for this bill —
     * but negative is not: it would manufacture a debt out of a balancing
     * pair.
     */
    amountMinor: integer("amount_minor").notNull(),

    /**
     * The original input, scaled by a million: "2:1:1" or "50/30/20". Null for
     * an exact split, where the amount was the input.
     *
     * An integer rather than a decimal, because the client models it as an
     * integer: `weightMicros` all the way from the split editor to this
     * column, with no conversion at either boundary to get wrong.
     */
    weightMicros: integer("weight_micros"),
  },
  (table) => [primaryKey({ columns: [table.entryId, table.memberId] }), check("entry_shares_amount_not_negative", sql`${table.amountMinor} >= 0`)],
);

/**
 * The record of what happened.
 *
 * Editing an expense in place is the right model — the entry row stays the one
 * source of truth, so the balance fold never has to know history exists — but
 * on its own it is silently destructive. Somebody who agreed a bill was ₹400
 * and settled on it would watch their balance move with nothing anywhere to
 * say why, or who did it.
 *
 * Every committed change appends one row here, written by the Durable Object
 * from what it just committed. There is no client-facing write path and no
 * diff on the wire: a client that authors its own history can describe a ₹400
 * → ₹4,000 edit as a ten-rupee correction, and nothing on the server could
 * tell. Deriving the record here removes the claim from the wire altogether.
 *
 * Still not event sourcing. Nothing is ever rebuilt from these rows: balances
 * read `entries` and only `entries`, so a bug in this machinery can make the
 * feed wrong and can never make a balance wrong.
 */
export const events = sqliteTable(
  "events",
  {
    id: text("id").primaryKey(),

    /**
     * Who was holding the pen, as a member id.
     *
     * Nullable, and that is not laxness. A join is attributed to nobody, which
     * is correct — the feed line is "Priya joined", and there is no third
     * party who did it to her. "Something changed and we cannot say who" is a
     * better audit line than silence.
     */
    actorId: text("actor_id").references(() => members.id),

    createdAt: text("created_at").notNull(),

    /** `entry` is an expense snapshot, the one kind whose detail the client derives by comparing consecutive rows. */
    kind: text("kind", { enum: eventKinds }).notNull(),

    /**
     * The entry, member or token this is about. Null for the kinds whose
     * subject is the group itself.
     *
     * Deliberately not a foreign key: the record describes what was true at
     * the time, and a member or an expense disappearing must not rewrite what
     * happened.
     */
    subjectId: text("subject_id"),

    /** The after-image, in whatever shape the kind calls for. */
    payload: text("payload", { mode: "json" }).notNull().$type<EventPayload>(),

    seq: integer("seq").notNull(),

    /**
     * Position within the sequence number, so the feed has a total order.
     *
     * One change can append more than one line — a patch that renames and
     * archives a group is two things that happened — and those share a `seq`
     * and a `createdAt`, because both are taken once per change. Without this
     * the only tiebreak left is a random UUID, so a feed would occasionally
     * render "archived" above "renamed" and read backwards.
     *
     * The server can order by `rowid`, which is insertion order. A client
     * cannot: rows arrive in a JSON array and land in a table that has its own
     * idea of order. So the order is stated rather than implied.
     */
    ordinal: integer("ordinal").notNull().default(0),
  },
  (table) => [
    /**
     * Unique, because the client's ordering depends on it being so.
     *
     * `append` derives the ordinal by counting what is already at this `seq`,
     * which is correct only because a Durable Object runs one thing at a time.
     * That is a true fact about the runtime and a bad place to leave an
     * invariant: it holds by convention, and the failure it guards against —
     * two lines claiming the same position — is invisible on the server, which
     * can still fall back to `rowid`, and visible only on a device, as a feed
     * that renders "archived" above "renamed" and reads backwards.
     *
     * So it is stated. A second writer of this table, today or in three years,
     * fails loudly here rather than quietly on somebody's phone.
     */
    uniqueIndex("events_position").on(table.seq, table.ordinal),
    index("events_subject").on(table.subjectId, table.createdAt),
  ],
);

/**
 * An invite: one named placeholder, handed to one person.
 *
 * Possession of the token is the entire proof. The row is never readable by
 * whoever holds it — they are, by design, not a member yet — so there is no
 * read path here at all, only `peekInvite`, which answers what the link
 * already implies to anybody holding it.
 */
export const invites = sqliteTable(
  "invites",
  {
    token: text("token").primaryKey(),

    /** The placeholder slot this link hands over. */
    memberId: text("member_id")
      .notNull()
      .references(() => members.id),

    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),
    createdAt: text("created_at").notNull(),

    /** A link forwarded into a group chat lives forever; the token must not. */
    expiresAt: text("expires_at").notNull(),

    redeemedAt: text("redeemed_at"),
    /** A profile id: who it turned out to be. */
    redeemedBy: text("redeemed_by"),
  },
  (table) => [index("invites_member").on(table.memberId)],
);

/**
 * The group's one open link: bearer authority over membership.
 *
 * Whoever holds the token may join. That is a genuinely bigger claim than an
 * invite makes, and it is answered by making the door visible rather than by
 * adding a wall — minting and revoking are both on the record, and one live
 * link per group means the link in a chat is always the current link or no
 * link.
 *
 * "One live link" is the shape of the table: the group has one, so the row is
 * a singleton keyed on a constant. Two members tapping "share" at the same
 * moment are serialized by the object, and the second replaces the first —
 * which is what minting means.
 */
export const groupLink = sqliteTable("group_link", {
  /** Always `'live'`. There is one link, or there is none. */
  id: text("id").primaryKey(),
  token: text("token").notNull(),
  createdBy: text("created_by")
    .notNull()
    .references(() => members.id),
  createdAt: text("created_at").notNull(),

  /**
   * Shorter than an invite's fourteen days. A named invite is for one person
   * who may open it next week; an open link is for a group forming now, and
   * the longer it lives the longer a forwarded copy keeps working.
   */
  expiresAt: text("expires_at").notNull(),
  revokedAt: text("revoked_at"),
});

/**
 * Writes owed to D1, staged inside the transaction that caused them.
 *
 * The Durable Object is the truth; D1's `memberships` and `link_tokens` are a
 * derived index that exists so "my groups" does not mean asking every object,
 * and so a request can be refused cheaply before a stub is created.
 *
 * Staging the write here rather than issuing it inline is what makes the two
 * agree eventually: a `fetch` cannot join a `transactionSync`, so an inline D1
 * write that failed would leave the index behind the object with nothing left
 * to retry it. A row here commits or does not commit with the change itself,
 * and is flushed immediately afterwards — with an alarm behind it if that
 * flush fails.
 */
export const outbox = sqliteTable("outbox", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  kind: text("kind", { enum: ["membership", "link_token", "group_purged"] }).notNull(),

  /**
   * Typed as the union of what the three kinds carry, and narrowed on `kind`
   * where it is applied. Drizzle can type a column but cannot tie it to the
   * value of another one, so `pendingOutbox` does the pairing — in one place,
   * named, rather than by casting at each read.
   */
  payload: text("payload", { mode: "json" }).notNull().$type<OutboxPayload>(),
  attempts: integer("attempts").notNull().default(0),
  createdAt: text("created_at").notNull(),
});

/**
 * What this object owes its own future, and when.
 *
 * A Durable Object has exactly one alarm, and three things want it: flushing
 * the outbox after a failure, archiving the group when it goes quiet, and
 * purging it long after that. So the deadlines are rows and the alarm is
 * armed at the earliest of them.
 *
 * This is why there is no cron sweep for dormancy. An object schedules
 * itself, so one that has been quiet for three months costs exactly one alarm
 * rather than ninety nightly wake-ups that find nothing to do. The
 * reconciliation cron stays, because checking that D1 agrees with every object
 * is genuinely a sweep.
 */
export const schedule = sqliteTable("schedule", {
  name: text("name", { enum: ["outbox", "archive", "purge"] }).primaryKey(),
  dueAt: integer("due_at").notNull(),
});
