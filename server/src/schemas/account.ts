import { z } from "@hono/zod-openapi";

import { deviceTokens, platforms, profiles } from "../db/d1/schema";
import { createSelectSchema, IdSchema, NameSchema, TimestampSchema, UpiVpaSchema } from "./common";

/** The person behind an account, their devices, and deleting it. None of it is group-scoped. */

export const PlatformSchema = z.enum(platforms).openapi("Platform");

const profileRow = createSelectSchema(profiles, {
  id: () => IdSchema,
  displayName: () => NameSchema,
  upiVpa: () => UpiVpaSchema,
  updatedAt: () => TimestampSchema,
  deletedAt: () => TimestampSchema,
});

/** A null `displayName` means nobody chose one; a set `deletedAt` means the account is gone. */
export const ProfileSchema = profileRow.openapi("Profile");

/** Your own row: the session names it, so there is no id to point at a stranger. */
export const ProfileUpdateSchema = profileRow.pick({ displayName: true, upiVpa: true }).openapi("ProfileUpdate");

/**
 * One page of the profile feed, the one feed cursored on time: D1 has no
 * single writer to hand out a sequence number.
 */
export const ProfilePageSchema = z
  .object({
    profiles: z.array(ProfileSchema),
    /** Opaque. Send it back as `after`; null when the page is empty. */
    cursor: z.string().nullable(),
    hasMore: z.boolean(),
  })
  .openapi("ProfilePage");

export const ProfileListSchema = z.object({ profiles: z.array(ProfileSchema) }).openapi("ProfileList");

/** The groups this account is still in. */
export const GroupIdsSchema = z.object({ groupIds: z.array(IdSchema) }).openapi("GroupIds");

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
export type ProfileList = z.infer<typeof ProfileListSchema>;
export type GroupIds = z.infer<typeof GroupIdsSchema>;
export type Device = z.infer<typeof DeviceSchema>;
export type AccountDeletion = z.infer<typeof AccountDeletionSchema>;
