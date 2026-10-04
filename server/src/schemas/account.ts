import { z } from "@hono/zod-openapi";

import { deviceTokens, platforms, profiles } from "../db/d1/schema";
import { avatarFields, avatarRefinements, refineAvatar } from "./appearance";
import { createSelectSchema, IdSchema, NameSchema, SeqSchema, TimestampSchema, UpiVpaSchema } from "./common";

/** The person behind an account, their devices, and deleting it. None of it is group-scoped. */

export const PlatformSchema = z.enum(platforms).openapi("Platform");

const profileRow = createSelectSchema(profiles, {
  id: () => IdSchema,
  displayName: () => NameSchema,
  upiVpa: () => UpiVpaSchema,
  ...avatarRefinements,
  updatedAt: () => TimestampSchema,
  deletedAt: () => TimestampSchema,
  version: () => SeqSchema,
});

/** A null `displayName` means nobody chose one; a set `deletedAt` means the account is gone. */
export const ProfileSchema = profileRow.openapi("Profile");

/** Your own row: the session names it, so there is no id to point at a stranger. */
export const ProfileUpdateSchema = profileRow
  .pick({ displayName: true, upiVpa: true, ...avatarFields })
  .superRefine(refineAvatar)
  .openapi("ProfileUpdate");

/** One page of the profile feed, oldest version first. */
export const ProfilePageSchema = z
  .object({
    profiles: z.array(ProfileSchema),
    /** The newest version on the page, or the cursor sent when it is empty. Send it back as `since`. */
    seq: SeqSchema,
    hasMore: z.boolean(),
  })
  .openapi("ProfilePage");

/** An FCM registration token. Registering claims it for this session, since phones change hands. */
export const DeviceSchema = createSelectSchema(deviceTokens, { token: () => z.string().min(1).max(4096), platform: () => PlatformSchema })
  .pick({ token: true, platform: true })
  .openapi("Device");

export const DeviceForgottenSchema = z.object({ forgotten: z.boolean() }).openapi("DeviceForgotten");

export const AccountDeletionSchema = z
  .object({
    /** Groups where your member row became a placeholder. */
    forgotten: z.int().nonnegative(),
    /** Groups deleted because you were the last account in them. */
    purged: z.int().nonnegative(),
  })
  .openapi("AccountDeletion");

export type Profile = z.infer<typeof ProfileSchema>;
export type ProfileUpdate = z.infer<typeof ProfileUpdateSchema>;
export type ProfilePage = z.infer<typeof ProfilePageSchema>;
export type Device = z.infer<typeof DeviceSchema>;
export type AccountDeletion = z.infer<typeof AccountDeletionSchema>;
