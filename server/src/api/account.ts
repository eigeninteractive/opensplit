import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, inArray, isNull, or, sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { user } from "../auth-schema";
import type { AuthedEnv } from "../context";
import { deviceTokens, memberships, profiles } from "../db/d1/schema";
import { AccountDeletionSchema, DeviceSchema, ProfileListSchema, ProfilePageSchema, ProfileSchema, ProfileUpdateSchema } from "../schemas/account";
import { apiError, IdSchema, jsonResponse, TimestampSchema } from "../schemas/common";
import { refusals } from "./routing";

/**
 * The person, their devices, and ending the whole thing.
 *
 * Everything here is about an account rather than a group, which is why none
 * of it goes near a Durable Object — except the last route, which goes near
 * all of them at once.
 *
 * ## Who you can see
 *
 * Postgres answered this with a row-level-security policy: a profile is
 * visible if you share a group with its owner. That policy was a correlated
 * subquery evaluated per row, per request, and it was also the only place the
 * rule was written down — which meant reading it required reading SQL nobody
 * on the client could see.
 *
 * Here it is `visibleProfiles`, below, and it is the same rule: people you
 * share a live membership with, plus yourself. The derived index in D1 is what
 * makes it a plain query instead of a fan-out over every group's object, which
 * is the one question those objects genuinely cannot answer individually.
 */

const PROFILE_PAGE_MAX = 200;

const profileFeedRoute = createRoute({
  method: "get",
  operationId: "getProfiles",
  path: "/profiles",
  tags: ["sync"],
  summary: "Everybody you share a group with, plus yourself",
  description:
    "The one feed still cursored on a timestamp rather than a sequence number, and honestly so: profiles live in a database that several requests write concurrently, so there is nothing there that can hand out a monotonic integer the way a group's Durable Object can. Send `cursor` and `cursorId` back next time.",
  request: {
    query: z.object({
      since: TimestampSchema.optional().openapi({ param: { name: "since", in: "query" } }),
      sinceId: IdSchema.optional().openapi({ param: { name: "sinceId", in: "query" } }),
      limit: z.coerce.number().int().min(1).max(PROFILE_PAGE_MAX).default(100).openapi({ type: "integer", example: 100 }),
    }),
  },
  responses: { 200: jsonResponse(ProfilePageSchema, "The page, and where the feed stands"), 401: refusals[401] },
});

const profilesByIdRoute = createRoute({
  method: "get",
  operationId: "getProfilesByIds",
  path: "/profiles/by-ids",
  tags: ["sync"],
  summary: "Exactly these profiles, cursor or no cursor",
  description:
    "The one thing the feed structurally cannot do. A cursor orders changes within what you can already see; it cannot surface a row that only just became visible to you. When somebody claims a placeholder, their account may have been named years ago — the row is old, the cursor is past it, and no incremental pull will ever mention it again. Same visibility rule as the feed: ids you cannot see are simply absent.",
  request: {
    query: z.object({
      ids: z
        .string()
        .min(1)
        .openapi({ param: { name: "ids", in: "query" }, example: "0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f,0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e70", description: "Comma-separated profile ids, at most 200." }),
    }),
  },
  responses: { 200: jsonResponse(ProfileListSchema, "Those of them you can see"), 400: refusals[400], 401: refusals[401] },
});

const updateProfileRoute = createRoute({
  method: "put",
  operationId: "updateProfile",
  path: "/profile",
  tags: ["sync"],
  summary: "Your own name and payment handle",
  description:
    "Singular, and with no id in it: the row written is the one the session names. An endpoint that took an id would be an endpoint somebody could point at a stranger's payment handle. Both fields are required — null clears one — because an optional field that means 'leave it alone' cannot be told from a null on the wire, and clearing a payment handle has to be expressible.",
  request: { body: { required: true, content: { "application/json": { schema: ProfileUpdateSchema } } } },
  responses: { 200: jsonResponse(ProfileSchema, "Your profile, as stored"), 400: refusals[400], 401: refusals[401] },
});

const registerDeviceRoute = createRoute({
  method: "put",
  operationId: "registerDevice",
  path: "/devices",
  tags: ["devices"],
  summary: "Where to wake this account",
  description: "Idempotent, and a transfer rather than a refusal when the token already belongs to somebody else: a phone that changes hands keeps its registration token, so the previous owner's claim on it has to yield or their notifications follow the new one.",
  request: { body: { required: true, content: { "application/json": { schema: DeviceSchema } } } },
  responses: { 200: jsonResponse(DeviceSchema, "Registered"), 400: refusals[400], 401: refusals[401] },
});

const forgetDeviceRoute = createRoute({
  method: "delete",
  operationId: "forgetDevice",
  path: "/devices/{token}",
  tags: ["devices"],
  summary: "Stop waking this device",
  description: "Only removes a token that belongs to this account, so signing out on one phone cannot silence somebody else's.",
  request: {
    params: z.object({
      token: z
        .string()
        .min(1)
        .max(4096)
        .openapi({ param: { name: "token", in: "path" } }),
    }),
  },
  responses: { 200: jsonResponse(z.object({ forgotten: z.boolean() }).openapi("DeviceForgotten"), "Whether there was one to forget"), 401: refusals[401] },
});

const deleteAccountRoute = createRoute({
  method: "delete",
  operationId: "deleteAccount",
  path: "/account",
  tags: ["account"],
  summary: "Delete this account, permanently",
  description:
    "Not a sign-out and not recoverable. It does not remove other people's ledgers: money you paid, money you owe and the settlements between you are facts about their group as much as yours, so your member row keeps its name and loses its account — exactly the state of somebody a friend added who never signed up. A group where you were the last account holder is collected outright instead, because nobody left could ever read it again. The session is left alone; the caller decides what to do with the device.",
  responses: { 200: jsonResponse(AccountDeletionSchema, "What it did, group by group"), 401: refusals[401] },
});

export function accountRoutes(routes: OpenAPIHono<AuthedEnv>) {
  routes.openapi(profileFeedRoute, async (c) => {
    const self = c.var.session.userId;
    const { since, sinceId, limit } = c.req.valid("query");
    const db = c.var.db;

    /**
     * A keyset on the pair, not on the timestamp.
     *
     * `updatedAt` alone is not unique — two profiles renamed in the same
     * millisecond are entirely ordinary — and a boundary that falls between
     * them either repeats a row forever or skips one silently. SQLite compares
     * row values lexicographically, which is exactly the `(updated_at, id)`
     * index this table carries.
     *
     * Both halves or neither: a `since` with no `sinceId` would be a caller
     * asking for a cursor that cannot be resumed from, and answering it as
     * though it could is how a page gets skipped.
     */
    const after = since && sinceId ? sql`(${profiles.updatedAt}, ${profiles.id}) > (${since}, ${sinceId})` : undefined;

    const rows = await db
      .select()
      .from(profiles)
      .where(and(await visibleProfiles(db, self), after))
      .orderBy(profiles.updatedAt, profiles.id)
      // One more than asked for, which is how `hasMore` is answered without a
      // second count over the same predicate.
      .limit(limit + 1)
      .all();

    const page = rows.slice(0, limit);
    const last = page.at(-1);

    return c.json(
      {
        profiles: page,
        cursor: last?.updatedAt ?? null,
        cursorId: last?.id ?? null,
        hasMore: rows.length > limit,
      },
      200,
    );
  });

  routes.openapi(profilesByIdRoute, async (c) => {
    const self = c.var.session.userId;
    const ids = c.req
      .valid("query")
      .ids.split(",")
      .map((id) => id.trim())
      .filter((id) => id.length > 0);

    if (ids.length === 0 || ids.length > PROFILE_PAGE_MAX) {
      return c.json(apiError("malformed", `Ask for between 1 and ${PROFILE_PAGE_MAX} profiles.`), 400);
    }

    const db = c.var.db;
    const rows = await db
      .select()
      .from(profiles)
      .where(and(inArray(profiles.id, ids), await visibleProfiles(db, self)))
      .all();

    return c.json({ profiles: rows }, 200);
  });

  routes.openapi(updateProfileRoute, async (c) => {
    const self = c.var.session.userId;
    const { displayName, upiVpa } = c.req.valid("json");

    const [row] = await c.var.db.update(profiles).set({ displayName, upiVpa, updatedAt: new Date().toISOString() }).where(eq(profiles.id, self)).returning();

    // The profile is created by a databaseHook when the account is, so a
    // missing row means that hook did not run — a bug worth a 500 rather than
    // an insert here that would paper over it on every subsequent request.
    if (!row) throw new Error(`No profile for account ${self}`);
    return c.json(row, 200);
  });

  routes.openapi(registerDeviceRoute, async (c) => {
    const self = c.var.session.userId;
    const device = c.req.valid("json");

    await c.var.db
      .insert(deviceTokens)
      .values({ ...device, profileId: self, updatedAt: new Date().toISOString() })
      .onConflictDoUpdate({
        target: deviceTokens.token,
        set: { profileId: self, platform: device.platform, updatedAt: new Date().toISOString() },
      });

    return c.json(device, 200);
  });

  routes.openapi(forgetDeviceRoute, async (c) => {
    const self = c.var.session.userId;
    const { token } = c.req.valid("param");

    const gone = await c.var.db
      .delete(deviceTokens)
      .where(and(eq(deviceTokens.token, token), eq(deviceTokens.profileId, self)))
      .returning({ token: deviceTokens.token });

    return c.json({ forgotten: gone.length > 0 }, 200);
  });

  routes.openapi(deleteAccountRoute, async (c) => {
    const self = c.var.session.userId;
    const db = c.var.db;
    const now = new Date().toISOString();

    /**
     * Every group this account has ever been indexed into, including the ones
     * it has left.
     *
     * A left group is exactly where a stale member row would otherwise keep
     * pointing at a deleted account forever. The object answers "not a member
     * of this" harmlessly for anything the index got wrong, which is why this
     * can afford to ask widely rather than precisely.
     */
    const groups = await db.select({ groupId: memberships.groupId }).from(memberships).where(eq(memberships.profileId, self)).all();

    let forgotten = 0;
    let purged = 0;
    for (const { groupId } of groups) {
      const outcome = await c.env.GROUP.getByName(groupId).forgetProfile(self);
      if (outcome.forgotten) forgotten += 1;
      if (outcome.purged) purged += 1;
    }

    /**
     * The profile row stays, emptied, and that is the point of `deletedAt`.
     *
     * Names are not lost by this: each group's member row carries its own
     * display name, which is the ledger's record and stays exactly as it was.
     * What the row is for afterwards is the id — it must never be handed to a
     * new account, and anything still holding a reference deserves a definite
     * "this account is gone" rather than a silent absence.
     *
     * The payment handle goes with it. A UPI address belonging to an account
     * that no longer exists is money sent nowhere.
     */
    await db.update(profiles).set({ displayName: null, upiVpa: null, deletedAt: now, updatedAt: now }).where(eq(profiles.id, self));
    await db.delete(deviceTokens).where(eq(deviceTokens.profileId, self));
    await db.delete(memberships).where(eq(memberships.profileId, self));

    // Last, because everything above ran on this account's session. Sessions
    // and linked sign-in identities cascade from it.
    await db.delete(user).where(eq(user.id, self));

    return c.json({ forgotten, purged }, 200);
  });
}

/**
 * The visibility rule, written once.
 *
 * People you share a live membership with, plus yourself. `leftAt` is checked
 * on both sides on purpose: leaving a group should stop the updates flowing in
 * either direction, and nothing is lost by it, because a member row carries
 * its own display name and is what the app renders from.
 *
 * Two reads rather than a correlated subquery. The subquery is one round trip
 * and reads well, but it makes every page of the feed re-derive a set that
 * changes when somebody joins a group — perhaps twice a month — and it puts the
 * whole membership table inside the predicate of a keyset scan, where D1's
 * planner has to choose between the `profiles_updated` index and the join.
 * Resolving the set first keeps the paged query a plain indexed range.
 */
async function visibleProfiles(db: DrizzleD1Database, self: string) {
  const mine = await db
    .select({ groupId: memberships.groupId })
    .from(memberships)
    .where(and(eq(memberships.profileId, self), isNull(memberships.leftAt)))
    .all();

  if (mine.length === 0) return eq(profiles.id, self);

  const together = await db
    .selectDistinct({ profileId: memberships.profileId })
    .from(memberships)
    .where(
      and(
        inArray(
          memberships.groupId,
          mine.map((row) => row.groupId),
        ),
        isNull(memberships.leftAt),
      ),
    )
    .all();

  return or(
    eq(profiles.id, self),
    inArray(
      profiles.id,
      together.map((row) => row.profileId),
    ),
  );
}
