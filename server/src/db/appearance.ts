import { type SQL, sql } from "drizzle-orm";
import { check, type SQLiteColumn, text } from "drizzle-orm/sqlite-core";

/**
 * How a person or a group looks: the avatar both have, and the cover only a
 * group has. Shared by the profile row in D1 and the group row in its object,
 * so the two cannot drift apart.
 *
 * An avatar is a `kind` plus the one field that kind reads, the same shape as
 * an event's payload: exactly that field is set, every other one is null. The
 * row therefore says what is shown and nothing else.
 */

export const avatarKinds = ["initials", "emoji", "icon", "photo"] as const;

/**
 * Hues an avatar's background can take. The device turns each into a tonal
 * pair harmonised with its own colours, so a name here is a choice of hue,
 * not of an exact colour.
 */
export const avatarColors = ["purple", "blue", "teal", "green", "olive", "amber", "orange", "pink"] as const;

/** Material Symbols names offered as an avatar. The device draws them, so the set is closed. */
export const avatarIcons = [
  "flight",
  "luggage",
  "beach_access",
  "hiking",
  "sailing",
  "train",
  "directions_car",
  "home",
  "apartment",
  "restaurant",
  "local_cafe",
  "local_bar",
  "celebration",
  "cake",
  "sports_soccer",
  "sports_cricket",
  "sports_basketball",
  "fitness_center",
  "music_note",
  "school",
  "work",
  "pets",
  "favorite",
  "family_restroom",
] as const;

/** A generated cover is drawn on the device from the group's own spending, so nothing about it is stored. */
export const coverKinds = ["generated", "photo"] as const;

export type AvatarKind = (typeof avatarKinds)[number];

/** A fresh set of avatar columns; each table needs its own builders. */
export const avatarColumns = () => ({
  avatarKind: text("avatar_kind", { enum: avatarKinds }).notNull().default("initials"),
  /** Null until somebody picks one: the device derives a hue from the id, so it never changes by itself. */
  avatarColor: text("avatar_color", { enum: avatarColors }),
  avatarEmoji: text("avatar_emoji"),
  avatarIcon: text("avatar_icon", { enum: avatarIcons }),
  /** An uploaded image's key in the media store. */
  avatarPhoto: text("avatar_photo"),
});

/** The group's cover. */
export const coverColumns = () => ({
  coverKind: text("cover_kind", { enum: coverKinds }).notNull().default("generated"),
  /** An uploaded image's key in the media store. */
  coverPhoto: text("cover_photo"),
});

/** The field each avatar kind reads, set exactly when that kind is chosen. */
export function avatarChecks(name: string, table: { avatarKind: SQLiteColumn; avatarEmoji: SQLiteColumn; avatarIcon: SQLiteColumn; avatarPhoto: SQLiteColumn }) {
  const exactlyWhen = (kind: AvatarKind, column: SQLiteColumn): SQL => sql`(${table.avatarKind} = ${sql.raw(`'${kind}'`)}) = (${column} is not null)`;
  return [check(`${name}_avatar_emoji`, exactlyWhen("emoji", table.avatarEmoji)), check(`${name}_avatar_icon`, exactlyWhen("icon", table.avatarIcon)), check(`${name}_avatar_photo`, exactlyWhen("photo", table.avatarPhoto))];
}

export function coverChecks(name: string, table: { coverKind: SQLiteColumn; coverPhoto: SQLiteColumn }) {
  return [check(`${name}_cover_photo`, sql`(${table.coverKind} = 'photo') = (${table.coverPhoto} is not null)`)];
}

/** A person's avatar as they start out: initials, on a hue derived from their id. */
export const defaultAvatar = { avatarKind: "initials", avatarColor: null, avatarEmoji: null, avatarIcon: null, avatarPhoto: null } as const;

/** A group as it starts out: initials and a cover drawn from its spending. */
export const defaultGroupLook = { ...defaultAvatar, coverKind: "generated", coverPhoto: null } as const;
