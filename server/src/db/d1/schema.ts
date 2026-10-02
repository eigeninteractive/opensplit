import { index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

import { avatarChecks, avatarColumns } from "../appearance";

/**
 * What D1 holds: profiles, plus derived indexes over the group objects (which
 * are the truth), plus Better Auth's tables in `src/auth-schema.ts`.
 * Timestamps are ISO-8601 strings, so lexical order is chronological.
 */

export const linkKinds = ["invite", "group_link"] as const;
export type LinkKind = (typeof linkKinds)[number];

export const platforms = ["android", "web"] as const;

/** A person as the app displays them; one row per account, created by a databaseHook. */
export const profiles = sqliteTable(
  "profiles",
  {
    id: text("id").primaryKey(),
    /** Null until chosen; a claimed invite adopts the placeholder's name only then. */
    displayName: text("display_name"),
    upiVpa: text("upi_vpa"),
    ...avatarColumns(),
    updatedAt: text("updated_at").notNull(),
    /** Set by account deletion; the row stays so history still resolves. */
    deletedAt: text("deleted_at"),
  },
  (table) => [index("profiles_updated").on(table.updatedAt, table.id), ...avatarChecks("profiles", table)],
);

/**
 * Which groups a person is in. Derived from the group objects, which send
 * every change in order and retry until D1 takes it.
 */
export const memberships = sqliteTable(
  "memberships",
  {
    profileId: text("profile_id").notNull(),
    groupId: text("group_id").notNull(),
    leftAt: text("left_at"),
    updatedAt: text("updated_at").notNull(),
    /** The group's outbox id for this write: an older write arriving late is ignored. */
    version: integer("version").notNull(),
  },
  (table) => [primaryKey({ columns: [table.profileId, table.groupId] }), index("memberships_group").on(table.groupId)],
);

/** Where to wake somebody. */
export const deviceTokens = sqliteTable(
  "device_tokens",
  {
    token: text("token").primaryKey(),
    profileId: text("profile_id").notNull(),
    platform: text("platform", { enum: platforms }).notNull(),
    updatedAt: text("updated_at").notNull(),
  },
  (table) => [index("device_tokens_profile").on(table.profileId)],
);

/**
 * Routes a token to its group before the holder is a member. Insert-only, since
 * a token never moves between groups; whether it still works is the object's call.
 */
export const linkTokens = sqliteTable(
  "link_tokens",
  {
    token: text("token").primaryKey(),
    groupId: text("group_id").notNull(),
    kind: text("kind", { enum: linkKinds }).notNull(),
    createdAt: text("created_at").notNull(),
  },
  (table) => [index("link_tokens_group").on(table.groupId)],
);

/** Groups that were collected. No index write for one is accepted afterwards, however late it arrives. */
export const purgedGroups = sqliteTable("purged_groups", {
  groupId: text("group_id").primaryKey(),
  purgedAt: text("purged_at").notNull(),
});
