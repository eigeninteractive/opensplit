import { z } from "@hono/zod-openapi";

import { profiles } from "../db/d1/schema";
import { createSelectSchema, IdSchema, TimestampSchema } from "./common";
import { UpiVpaSchema } from "./ledger";

/**
 * The person behind the account, their devices, and ending the whole thing.
 *
 * Separate from `ledger.ts` because none of it is group-scoped. A profile is a
 * person across the app; a member is that person's place in one group. Nothing
 * financial ever references a profile, which is exactly what lets a group hold
 * people who have no account at all — and what lets an account be deleted
 * without disturbing anybody else's balances.
 */

/**
 * A person across the app. A null `displayName` means nobody has said who
 * this is, which the app treats differently from any name. A set `deletedAt`
 * means the account is gone: the row stays so history still resolves a name,
 * and a device stops offering to pay them.
 */
export const ProfileSchema = createSelectSchema(profiles, {
  updatedAt: TimestampSchema,
  deletedAt: TimestampSchema.nullable(),
}).openapi("Profile");

/**
 * Your own name and payment handle, both of them, every time.
 *
 * There is deliberately no `id`: the row written is the one the session names.
 * An endpoint that took an id would be an endpoint somebody could point at a
 * stranger's payment handle, and the only defence would be a check that this
 * shape makes unnecessary.
 *
 * Both fields, every time, like every other body here (see `ledger.ts`).
 */
export const ProfileUpdateSchema = z
  .object({
    displayName: z.string().trim().min(1).max(100).nullable(),
    upiVpa: UpiVpaSchema.nullable(),
  })
  .openapi("ProfileUpdate");

/**
 * One page of the profile feed.
 *
 * The one feed still cursored on a timestamp rather than on a sequence number,
 * and honestly so: profiles live in D1, which several requests write
 * concurrently, so there is nothing there that can hand out a monotonic
 * integer the way a group's Durable Object can for its own rows.
 *
 * The cursor is the `(updatedAt, id)` pair from the last row, because
 * `updatedAt` alone is not unique — two profiles renamed in the same
 * millisecond would make a page boundary either repeat a row forever or skip
 * one silently.
 */
export const ProfilePageSchema = z
  .object({
    profiles: z.array(ProfileSchema),

    /** Where the feed stands after `profiles`, or null when it is empty. */
    cursor: TimestampSchema.nullable(),
    cursorId: IdSchema.nullable(),
    hasMore: z.boolean(),
  })
  .openapi("ProfilePage");

/** Exactly the profiles asked for, in no particular order. */
export const ProfileListSchema = z
  .object({
    profiles: z.array(ProfileSchema),
  })
  .openapi("ProfileList");

/**
 * Where to wake somebody.
 *
 * `token` is FCM's registration token for one installation. It moves between
 * accounts — somebody signs out and a friend signs in on the same phone — so
 * registering claims it for the session that asked rather than refusing.
 */
export const DeviceSchema = z
  .object({
    token: z.string().min(1).max(4096),
    platform: z.enum(["android", "web"]),
  })
  .openapi("Device");

/**
 * What deleting the account did, group by group.
 *
 * Reported rather than swallowed, because the two outcomes are genuinely
 * different and somebody deleting their account is entitled to know which
 * happened: a group with other account holders keeps its ledger and loses your
 * account from it, while a group nobody left could ever read again is
 * destroyed outright.
 */
export const AccountDeletionSchema = z
  .object({
    /** Groups where your member row became a placeholder again. */
    forgotten: z.int().nonnegative(),

    /** Groups deleted entirely, because you were the last account in them. */
    purged: z.int().nonnegative(),
  })
  .openapi("AccountDeletion");

export type Profile = z.infer<typeof ProfileSchema>;
export type ProfileUpdate = z.infer<typeof ProfileUpdateSchema>;
export type ProfilePage = z.infer<typeof ProfilePageSchema>;
export type ProfileList = z.infer<typeof ProfileListSchema>;
export type Device = z.infer<typeof DeviceSchema>;
export type AccountDeletion = z.infer<typeof AccountDeletionSchema>;
