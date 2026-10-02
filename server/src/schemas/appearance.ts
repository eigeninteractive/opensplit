import { z } from "@hono/zod-openapi";

import { avatarColors, avatarIcons, avatarKinds, coverKinds } from "../db/appearance";

/** How a person or a group looks, on the wire. See `db/appearance.ts`. */

export const AvatarKindSchema = z.enum(avatarKinds).openapi("AvatarKind");
export const AvatarColorSchema = z.enum(avatarColors).openapi("AvatarColor");
export const AvatarIconSchema = z.enum(avatarIcons).openapi("AvatarIcon");
export const CoverKindSchema = z.enum(coverKinds).openapi("CoverKind");

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });

/** One emoji: a single grapheme that is a pictograph or a flag. */
export const EmojiSchema = z
  .string()
  .max(32)
  .refine((text) => [...segmenter.segment(text)].length === 1 && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(text), "Not a single emoji.")
  .openapi({ example: "🏖️" });

/** Where an uploaded image lives in the media store. */
export const MediaKeySchema = z
  .string()
  .regex(/^[a-z0-9][a-z0-9/_-]{0,127}\.[a-z0-9]{2,5}$/)
  .openapi({ example: "avatars/0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f/4f2a.webp" });

/** The column refinements a row derived from a table with avatar columns needs. */
export const avatarRefinements = {
  avatarKind: () => AvatarKindSchema,
  avatarColor: () => AvatarColorSchema,
  avatarEmoji: () => EmojiSchema,
  avatarIcon: () => AvatarIconSchema,
  avatarPhoto: () => MediaKeySchema,
};

export const coverRefinements = {
  coverKind: () => CoverKindSchema,
  coverPhoto: () => MediaKeySchema,
};

/** Which of the columns an input body carries. */
export const avatarFields = { avatarKind: true, avatarColor: true, avatarEmoji: true, avatarIcon: true, avatarPhoto: true } as const;
export const coverFields = { coverKind: true, coverPhoto: true } as const;

type AvatarInput = { avatarKind: string; avatarEmoji: string | null; avatarIcon: string | null; avatarPhoto: string | null };
type CoverInput = { coverKind: string; coverPhoto: string | null };

/**
 * The checks every body with an avatar makes: the kind's own field is set and
 * no other is, and no photo is named while nothing can be uploaded.
 *
 * Photos are in the shape so that turning uploads on later is a new route and
 * an existence check here, not a change to any row.
 */
export function refineAvatar(input: AvatarInput, context: z.RefinementCtx): void {
  const fields = { emoji: input.avatarEmoji, icon: input.avatarIcon, photo: input.avatarPhoto } as const;
  for (const [kind, value] of Object.entries(fields)) {
    if ((input.avatarKind === kind) !== (value !== null)) {
      const field = `avatar${kind[0]?.toUpperCase()}${kind.slice(1)}`;
      context.addIssue({ code: "custom", path: [field], message: `${field} is set exactly when avatarKind is ${kind}.` });
    }
  }
  if (input.avatarPhoto !== null) context.addIssue({ code: "custom", path: ["avatarPhoto"], message: "Photos cannot be uploaded yet." });
}

export function refineCover(input: CoverInput, context: z.RefinementCtx): void {
  if ((input.coverKind === "photo") !== (input.coverPhoto !== null)) {
    context.addIssue({ code: "custom", path: ["coverPhoto"], message: "coverPhoto is set exactly when coverKind is photo." });
  }
  if (input.coverPhoto !== null) context.addIssue({ code: "custom", path: ["coverPhoto"], message: "Photos cannot be uploaded yet." });
}
