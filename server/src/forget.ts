import { and, eq, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";

import { user } from "./auth-schema";
import { defaultAvatar } from "./db/appearance";
import { deviceTokens, memberships, profiles } from "./db/d1/schema";

/**
 * Taking a deleted account out of every group it was in: each place becomes a
 * placeholder under the name the account last had, or, given an `heir`, that
 * account's place instead.
 *
 * The caller deletes the `user` row first. From that moment no group can add
 * a membership for the account (D1 refuses one, and the group forgets the
 * account itself), so the memberships read here are complete. A row is
 * removed only after its group has confirmed, which makes the remaining rows
 * the list of unfinished work if this is interrupted: `finishDeletions` picks
 * them up, as plain forgetting.
 */
export async function forgetAccount(env: Env, profileId: string, { heir }: { heir?: string } = {}): Promise<{ forgotten: number; purged: number }> {
  const db = drizzle(env.DB);
  // The placeholders left behind keep the name the account last had, so the profile is emptied last.
  const name = (await db.select({ displayName: profiles.displayName }).from(profiles).where(eq(profiles.id, profileId)).get())?.displayName ?? null;
  const groups = await db.select({ groupId: memberships.groupId }).from(memberships).where(eq(memberships.profileId, profileId)).all();

  let forgotten = 0;
  let purged = 0;
  for (const { groupId } of groups) {
    const group = env.GROUP.getByName(groupId);
    const outcome = heir === undefined ? await group.forgetProfile(profileId, name) : await group.handOver(profileId, heir);
    if (outcome.forgotten) forgotten += 1;
    if (outcome.purged) purged += 1;
    await db.delete(memberships).where(and(eq(memberships.profileId, profileId), eq(memberships.groupId, groupId)));
  }

  // Kept, emptied, so co-members' history still resolves.
  const now = new Date().toISOString();
  await db
    .update(profiles)
    .set({ displayName: null, upiVpa: null, ...defaultAvatar, deletedAt: now, updatedAt: now })
    .where(eq(profiles.id, profileId));
  return { forgotten, purged };
}

/**
 * A guest signed in to an account that already existed. Both are the same
 * person, so the guest's places go to that account and the guest account
 * ends: its session on this device was replaced, and nothing else could ever
 * reach it.
 */
export async function handOverGuest(env: Env, guestId: string, heirId: string): Promise<void> {
  const db = drizzle(env.DB);
  await db.batch([db.delete(deviceTokens).where(eq(deviceTokens.profileId, guestId)), db.delete(user).where(eq(user.id, guestId))]);
  await forgetAccount(env, guestId, { heir: heirId });
}

const FINISH_BATCH = 100;

/** Completes deletions a request started and did not finish: accounts that are gone but still named in D1. */
export async function finishDeletions(env: Env): Promise<number> {
  const db = drizzle(env.DB);
  const unfinished = await db.all<{ id: string }>(sql`
    select profile_id as id from ${memberships}
     where not exists (select 1 from ${user} where ${user.id} = ${memberships.profileId})
    union
    select id from ${profiles}
     where ${profiles.deletedAt} is null and not exists (select 1 from ${user} where ${user.id} = ${profiles.id})
    limit ${FINISH_BATCH}`);

  for (const { id } of unfinished) await forgetAccount(env, id);
  if (unfinished.length > 0) console.log("[sweep] finished", unfinished.length, "interrupted account deletions");
  return unfinished.length;
}
