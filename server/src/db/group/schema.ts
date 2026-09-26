import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, real, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

import type { EntrySnapshot, GroupEventPayload, LinkEventPayload, MemberEventPayload } from "../../schemas/ledger";
import type { LinkKind } from "../d1/schema";

/**
 * One group's ledger, inside its Durable Object.
 *
 * No table has a `group_id`: the object is the group, so the scope is the
 * address of the database. Timestamps are ISO-8601 UTC strings, as on the
 * wire. CHECK constraints catch our own bugs; nothing else can reach these
 * tables.
 */

export const entryKinds = ["expense", "settlement"] as const;
export const splitKinds = ["equal", "exact", "shares", "percent"] as const;

/** Event kinds, grouped by the payload each group carries. */
export const memberEventKinds = ["member_added", "member_joined", "member_left", "member_renamed"] as const;
export const groupEventKinds = ["group_renamed", "group_archived", "group_restored"] as const;
export const linkEventKinds = ["link_created", "link_revoked"] as const;
export const eventKinds = ["entry", ...memberEventKinds, ...groupEventKinds, ...linkEventKinds] as const;

export type MemberEventKind = (typeof memberEventKinds)[number];
export type GroupEventKind = (typeof groupEventKinds)[number];
export type LinkEventKind = (typeof linkEventKinds)[number];

/** The sequence allocator: one strictly increasing number per committed change. */
export const counter = sqliteTable("counter", {
  name: text("name").primaryKey(),
  value: integer("value").notNull(),
});

/** A member. A null `profileId` is a placeholder: a real person with no account yet. */
export const members = sqliteTable(
  "members",
  {
    id: text("id").primaryKey(),
    profileId: text("profile_id"),
    displayName: text("display_name").notNull(),
    /** Payment handle in this group; falls back to the profile's when null. */
    upiVpa: text("upi_vpa"),
    joinedAt: text("joined_at").notNull(),
    /** Members are never deleted, so their entries stay meaningful. */
    leftAt: text("left_at"),
    updatedAt: text("updated_at").notNull(),
    seq: integer("seq").notNull(),
  },
  (table) => [
    // NULLs are distinct, so placeholders coexist while one account holds at most one place.
    uniqueIndex("members_profile").on(table.profileId),
    index("members_seq").on(table.seq),
    check("members_name_not_blank", sql`length(trim(${table.displayName})) > 0`),
  ],
);

/** The group itself. `createdBy` is a member id and describes; it never authorizes. */
export const meta = sqliteTable(
  "meta",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull(),
    defaultCurrency: text("default_currency").notNull(),
    /** A 1:1 split is a two-member group with this set. */
    isDirect: integer("is_direct", { mode: "boolean" }).notNull().default(false),
    simplifyDebts: integer("simplify_debts", { mode: "boolean" }).notNull().default(true),
    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),
    createdAt: text("created_at").notNull(),
    archivedAt: text("archived_at"),
    updatedAt: text("updated_at").notNull(),
    seq: integer("seq").notNull(),
  },
  (table) => [check("meta_name_not_blank", sql`length(trim(${table.name})) > 0`)],
);

/** What remains after a group is collected, so the feed can tell devices to drop it. */
export const tombstone = sqliteTable("tombstone", {
  /** Always `'purged'`. */
  id: text("id").primaryKey(),
  groupId: text("group_id").notNull(),
  purgedAt: text("purged_at").notNull(),
  seq: integer("seq").notNull(),
});

export const entries = sqliteTable(
  "entries",
  {
    id: text("id").primaryKey(),
    /** A settlement is an entry with one payer and one share. */
    kind: text("kind", { enum: entryKinds }).notNull().default("expense"),
    description: text("description").notNull().default(""),
    categoryId: text("category_id"),
    /** The currency it was spent in; never converted on write. */
    currency: text("currency").notNull(),
    amountMinor: integer("amount_minor").notNull(),
    /** A calendar date, `YYYY-MM-DD`. */
    entryDate: text("entry_date").notNull(),
    /** When and where it happened, from the device clock: both or neither. Display only. */
    occurredAt: text("occurred_at"),
    timeZone: text("time_zone"),
    splitKind: text("split_kind", { enum: splitKinds }).notNull().default("equal"),
    /** Display-only rate to the group currency on `entryDate`; never enters a balance. */
    fxRate: real("fx_rate"),
    fxSource: text("fx_source"),
    fxAt: text("fx_at"),
    notes: text("notes"),
    /** A member id, resolved from the session; never a parameter. */
    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),
    /** Client-minted, so a retried push is idempotent. */
    clientKey: text("client_key"),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
    /** Soft delete, so the deletion travels through the feed. */
    deletedAt: text("deleted_at"),
    seq: integer("seq").notNull(),
  },
  (table) => [
    index("entries_seq").on(table.seq),
    uniqueIndex("entries_client_key").on(table.clientKey),
    check("entries_amount_positive", sql`${table.amountMinor} > 0`),
    check("entries_fx_rate_positive", sql`${table.fxRate} is null or ${table.fxRate} > 0`),
    check("entries_moment_complete", sql`(${table.occurredAt} is null) = (${table.timeZone} is null)`),
    check("entries_fx_complete", sql`(${table.fxRate} is null) = (${table.fxSource} is null) and (${table.fxRate} is null) = (${table.fxAt} is null)`),
  ],
);

/** Payers and shares travel with their entry and share its `seq`. */
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
    /** Zero is somebody present who owes nothing. */
    amountMinor: integer("amount_minor").notNull(),
    /** The input weight scaled by a million ("2:1:1", "50/30/20"); null for an exact split. */
    weightMicros: integer("weight_micros"),
  },
  (table) => [primaryKey({ columns: [table.entryId, table.memberId] }), check("entry_shares_amount_not_negative", sql`${table.amountMinor} >= 0`)],
);

/**
 * The activity record, written by the object from what it committed. Never
 * read by balances.
 *
 * Exactly one payload column is set, chosen by `kind`: `entry` for an expense
 * snapshot, `member`, `group` or `link` for the other kind groups above.
 */
export const events = sqliteTable(
  "events",
  {
    id: text("id").primaryKey(),
    /** Who did it, as a member id. Null when nobody did (a join, the dormancy alarm). */
    actorId: text("actor_id").references(() => members.id),
    createdAt: text("created_at").notNull(),
    kind: text("kind", { enum: eventKinds }).notNull(),
    /** The entry, member or token it is about; null for the group itself. Not a foreign key. */
    subjectId: text("subject_id"),
    entry: text("entry", { mode: "json" }).$type<EntrySnapshot>(),
    member: text("member", { mode: "json" }).$type<MemberEventPayload>(),
    group: text("group", { mode: "json" }).$type<GroupEventPayload>(),
    link: text("link", { mode: "json" }).$type<LinkEventPayload>(),
    seq: integer("seq").notNull(),
    /** Position within one change, which can append several lines. */
    ordinal: integer("ordinal").notNull().default(0),
  },
  (table) => [uniqueIndex("events_position").on(table.seq, table.ordinal), index("events_subject").on(table.subjectId, table.createdAt), check("events_one_payload", sql`(${table.entry} is not null) + (${table.member} is not null) + (${table.group} is not null) + (${table.link} is not null) = 1`)],
);

/** An invite: one placeholder handed to whoever holds the token. */
export const invites = sqliteTable(
  "invites",
  {
    token: text("token").primaryKey(),
    memberId: text("member_id")
      .notNull()
      .references(() => members.id),
    createdBy: text("created_by")
      .notNull()
      .references(() => members.id),
    createdAt: text("created_at").notNull(),
    expiresAt: text("expires_at").notNull(),
    redeemedAt: text("redeemed_at"),
    /** A profile id. */
    redeemedBy: text("redeemed_by"),
  },
  (table) => [index("invites_member").on(table.memberId)],
);

/** The group's one open link. A singleton row keyed `'live'`; minting replaces it. */
export const groupLink = sqliteTable("group_link", {
  id: text("id").primaryKey(),
  token: text("token").notNull(),
  createdBy: text("created_by")
    .notNull()
    .references(() => members.id),
  createdAt: text("created_at").notNull(),
  expiresAt: text("expires_at").notNull(),
  revokedAt: text("revoked_at"),
});

export const outboxKinds = ["membership", "link_token", "group_purged"] as const;

export type MembershipWrite = { groupId: string; profileId: string; leftAt: string | null; updatedAt: string };
export type LinkTokenWrite = { groupId: string; token: string; tokenKind: LinkKind; revoked: boolean };
export type PurgeWrite = { groupId: string };

/**
 * D1 index writes, staged in the transaction that caused them and flushed
 * afterwards (retried by the alarm on failure).
 */
export const outbox = sqliteTable("outbox", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  kind: text("kind", { enum: outboxKinds }).notNull(),
  payload: text("payload", { mode: "json" }).notNull().$type<MembershipWrite | LinkTokenWrite | PurgeWrite>(),
  attempts: integer("attempts").notNull().default(0),
  createdAt: text("created_at").notNull(),
});

export const chores = ["outbox", "archive", "purge"] as const;
export type Chore = (typeof chores)[number];

/** Deadlines owed to the object's single alarm, which is armed at the earliest. */
export const schedule = sqliteTable("schedule", {
  name: text("name", { enum: chores }).primaryKey(),
  dueAt: integer("due_at").notNull(),
});
