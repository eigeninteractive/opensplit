import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, inArray, isNull, or, sql } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { user } from "../auth-schema";
import { chunked } from "../chunked";
import type { AppEnv } from "../context";
import { deviceTokens, memberships, profiles } from "../db/d1/schema";
import { AccountDeletionSchema, DeviceForgottenSchema, DeviceSchema, ProfileListSchema, ProfilePageSchema, ProfileSchema, ProfileUpdateSchema } from "../schemas/account";
import { apiError, IdSchema, jsonBody, jsonResponse } from "../schemas/common";
import { refusals, signedIn } from "./routing";

/** The person, their devices, and ending the account. */

const PAGE_MAX = 200;

const profileFeedRoute = createRoute({
  ...signedIn,
  method: "get",
  operationId: "getProfiles",
  path: "/profiles",
  tags: ["sync"],
  summary: "Everybody you share a group with, plus yourself",
  description: "Cursored on time, since profiles have no single writer to number them. Send `cursor` back as `after`.",
  request: {
    query: z.object({
      after: z
        .string()
        .optional()
        .openapi({ param: { name: "after", in: "query" } }),
      limit: z.coerce.number().int().min(1).max(PAGE_MAX).default(100).openapi({ type: "integer", example: 100 }),
    }),
  },
  responses: { 200: jsonResponse(ProfilePageSchema, "The page, and where the feed stands"), 400: refusals[400], 401: refusals[401] },
});

const profileLookupRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "lookupProfiles",
  path: "/profiles/lookup",
  tags: ["sync"],
  summary: "Exactly these profiles",
  description: "For a profile that just became visible (a placeholder was claimed) but is older than the feed's cursor. Ids you cannot see are absent.",
  request: { body: jsonBody(z.object({ ids: z.array(IdSchema).min(1).max(PAGE_MAX) }).openapi("ProfileLookup")) },
  responses: { 200: jsonResponse(ProfileListSchema, "Those of them you can see"), 400: refusals[400], 401: refusals[401] },
});

const updateProfileRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "updateProfile",
  path: "/profile",
  tags: ["sync"],
  summary: "Your own name and payment handle",
  request: { body: jsonBody(ProfileUpdateSchema) },
  responses: { 200: jsonResponse(ProfileSchema, "Your profile, as stored"), 400: refusals[400], 401: refusals[401] },
});

const registerDeviceRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "registerDevice",
  path: "/devices",
  tags: ["devices"],
  summary: "Where to wake this account",
  description: "Idempotent, and a transfer when the token belonged to somebody else: phones change hands.",
  request: { body: jsonBody(DeviceSchema) },
  responses: { 200: jsonResponse(DeviceSchema, "Registered"), 400: refusals[400], 401: refusals[401] },
});

const forgetDeviceRoute = createRoute({
  ...signedIn,
  method: "delete",
  operationId: "forgetDevice",
  path: "/devices/{token}",
  tags: ["devices"],
  summary: "Stop waking this device",
  description: "Only removes a token that belongs to this account.",
  request: { params: z.object({ token: DeviceSchema.shape.token.openapi({ param: { name: "token", in: "path" } }) }) },
  responses: { 200: jsonResponse(DeviceForgottenSchema, "Whether there was one to forget"), 401: refusals[401] },
});

const deleteAccountRoute = createRoute({
  ...signedIn,
  method: "delete",
  operationId: "deleteAccount",
  path: "/account",
  tags: ["account"],
  summary: "Delete this account, permanently",
  description: "Other people's ledgers stay: your member rows become placeholders that keep your name. A group where you were the last account holder is collected. The session is left for the caller to clear.",
  responses: { 200: jsonResponse(AccountDeletionSchema, "What it did, group by group"), 401: refusals[401] },
});

export function accountRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(profileFeedRoute, async (c) => {
    const { after, limit } = c.req.valid("query");
    const position = after === undefined ? null : decodeCursor(after);
    if (position === undefined) return c.json(apiError("malformed", "That is not a cursor from this feed."), 400);

    const rows = await c.var.db
      .select()
      .from(profiles)
      .where(and(visibleTo(c.var.db, c.var.session.userId), position ? sql`(${profiles.updatedAt}, ${profiles.id}) > (${position.updatedAt}, ${position.id})` : undefined))
      .orderBy(profiles.updatedAt, profiles.id)
      .limit(limit + 1)
      .all();

    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return c.json({ profiles: page, cursor: last ? encodeCursor(last) : null, hasMore: rows.length > limit }, 200);
  });

  routes.openapi(profileLookupRoute, async (c) => {
    const visible = visibleTo(c.var.db, c.var.session.userId);
    const ids = chunked([...new Set(c.req.valid("json").ids)]);
    const pages = await Promise.all(
      ids.map((chunk) =>
        c.var.db
          .select()
          .from(profiles)
          .where(and(inArray(profiles.id, chunk), visible))
          .all(),
      ),
    );
    return c.json({ profiles: pages.flat() }, 200);
  });

  routes.openapi(updateProfileRoute, async (c) => {
    const { displayName, upiVpa } = c.req.valid("json");
    const [row] = await c.var.db.update(profiles).set({ displayName, upiVpa, updatedAt: new Date().toISOString() }).where(eq(profiles.id, c.var.session.userId)).returning();
    // Created by a databaseHook with the account, so a missing row is a bug, not a case.
    if (!row) throw new Error(`No profile for account ${c.var.session.userId}`);
    return c.json(row, 200);
  });

  routes.openapi(registerDeviceRoute, async (c) => {
    const device = c.req.valid("json");
    const claim = { profileId: c.var.session.userId, platform: device.platform, updatedAt: new Date().toISOString() };
    await c.var.db
      .insert(deviceTokens)
      .values({ token: device.token, ...claim })
      .onConflictDoUpdate({ target: deviceTokens.token, set: claim });
    return c.json(device, 200);
  });

  routes.openapi(forgetDeviceRoute, async (c) => {
    const gone = await c.var.db
      .delete(deviceTokens)
      .where(and(eq(deviceTokens.token, c.req.valid("param").token), eq(deviceTokens.profileId, c.var.session.userId)))
      .returning({ token: deviceTokens.token });
    return c.json({ forgotten: gone.length > 0 }, 200);
  });

  routes.openapi(deleteAccountRoute, async (c) => {
    const self = c.var.session.userId;
    const db = c.var.db;
    const now = new Date().toISOString();

    // Every group, including ones left: a left group still holds the member row.
    const groups = await db.select({ groupId: memberships.groupId }).from(memberships).where(eq(memberships.profileId, self)).all();

    let forgotten = 0;
    let purged = 0;
    for (const { groupId } of groups) {
      const outcome = await c.env.GROUP.getByName(groupId).forgetProfile(self);
      if (outcome.forgotten) forgotten += 1;
      if (outcome.purged) purged += 1;
    }

    // The profile stays, emptied, so co-members' history still resolves.
    await db.update(profiles).set({ displayName: null, upiVpa: null, deletedAt: now, updatedAt: now }).where(eq(profiles.id, self));
    await db.delete(deviceTokens).where(eq(deviceTokens.profileId, self));
    await db.delete(memberships).where(eq(memberships.profileId, self));
    // Last, since everything above ran on this account's session; sessions cascade.
    await db.delete(user).where(eq(user.id, self));

    return c.json({ forgotten, purged }, 200);
  });
}

/** Yourself, and everybody currently in a group with you. Subqueries, so nothing unbounded is bound. */
function visibleTo(db: DrizzleD1Database, self: string) {
  const mine = db
    .select({ groupId: memberships.groupId })
    .from(memberships)
    .where(and(eq(memberships.profileId, self), isNull(memberships.leftAt)));
  const together = db
    .select({ profileId: memberships.profileId })
    .from(memberships)
    .where(and(inArray(memberships.groupId, mine), isNull(memberships.leftAt)));
  return or(eq(profiles.id, self), inArray(profiles.id, together));
}

type Position = { updatedAt: string; id: string };

const encodeCursor = ({ updatedAt, id }: Position) => `${updatedAt}|${id}`;

/** A position, or undefined for something this feed did not issue. */
function decodeCursor(cursor: string): Position | undefined {
  const [updatedAt, id, ...rest] = cursor.split("|");
  if (!updatedAt || !id || rest.length > 0 || Number.isNaN(Date.parse(updatedAt))) return undefined;
  return { updatedAt, id };
}
