import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { and, eq, inArray, isNull, lt, or } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { chunked } from "../chunked";
import type { AppEnv } from "../context";
import { memberships, profiles } from "../db/d1/schema";
import { wakeProfile } from "../push/fcm";
import type { Profile } from "../schemas/account";
import { apiError, jsonBody, jsonResponse } from "../schemas/common";
import {
  EntryInputSchema,
  EntrySchema,
  type GroupChanges,
  GroupInputSchema,
  type GroupRefusal,
  GroupSchema,
  type GroupSeen,
  GroupSeenSchema,
  type Member,
  MemberInputSchema,
  MemberSchema,
  PullRequestSchema,
  PullSchema,
  REMINDER_INTERVAL_SECONDS,
  ReminderInputSchema,
  ReminderSchema,
  SeenInputSchema,
} from "../schemas/ledger";
import { EntryPathSchema, GroupPathSchema, group, MemberPathSchema, refusals, refused, respond, signedIn } from "./routing";

/**
 * The sync surface. Handlers only route: rules about shape are the Zod
 * schemas', rules about who may do what are the group object's. There is no
 * D1 membership check first, because the index lags a join and the object
 * answers `not_member` itself.
 */

const pullRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "pull",
  path: "/sync",
  tags: ["sync"],
  summary: "Every group this account is in, and what changed in the ones asked for",
  description:
    "Each group asked for gets its own page past its own cursor, read in parallel; a group that cannot be read is listed in `refusals` and the rest are still answered. `groupIds` names every group the account is in now, so one with no cursor yet is asked for next time, from 0. A page is cut only between sequence numbers, so a device sees a whole write or none of it; send each page's `seq` back as that group's `since`.",
  request: { body: jsonBody(PullRequestSchema) },
  responses: { 200: jsonResponse(PullSchema, "The account's groups, and a page or a refusal for each group asked for"), 400: refusals[400], 401: refusals[401] },
});

const putGroupRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "putGroup",
  path: "/groups/{groupId}",
  tags: ["groups"],
  summary: "Make a group and its creator's place in it, or change shared settings",
  description: "Idempotent, so a retry whose response was lost returns the same group. Editing needs membership; creating does not.",
  request: { params: GroupPathSchema, body: jsonBody(GroupInputSchema) },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const putMemberRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "putMember",
  path: "/groups/{groupId}/members/{memberId}",
  tags: ["groups"],
  summary: "Add somebody who has never opened the app, or change a name, a payment handle, or whether somebody is still here",
  description: "Your own row and any placeholder are editable; another account holder's are not. Leaving or removing somebody requires them to be settled in every currency; leaving ends access. The last account holder can leave only when the entire group is settled, which permanently deletes the group.",
  request: { params: MemberPathSchema, body: jsonBody(MemberInputSchema) },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const putEntryRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "putEntry",
  path: "/groups/{groupId}/entries/{entryId}",
  tags: ["entries"],
  summary: "Record, edit, delete or restore an expense, whole",
  description: "`baseSeq` must be the version stored now (null for a new expense), or the write is refused as `stale_base`: the expense is replaced whole, so a write composed on an older version would undo the edit in between. Sending the stored contents again is answered with the stored row, whatever the base.",
  request: { params: EntryPathSchema, body: jsonBody(EntryInputSchema) },
  responses: { 200: jsonResponse(EntrySchema, "The expense as stored"), ...refusals },
});

const putSeenRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "putSeen",
  path: "/groups/{groupId}/seen",
  tags: ["groups"],
  summary: "Say how far this account has read a group's activity",
  description: "Kept per account, so a group read on one device is read on the others, which learn it from `seen` in their next pull. Only ever moves forward, and never past the server's clock: the answer is where it stands now, which may be later than what was sent.",
  request: { params: GroupPathSchema, body: jsonBody(SeenInputSchema) },
  responses: { 200: jsonResponse(GroupSeenSchema, "Where this account has read to"), 400: refusals[400], 401: refusals[401], 403: refusals[403] },
});

const remindRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "remind",
  path: "/groups/{groupId}/reminders",
  tags: ["groups"],
  summary: "Notify somebody who owes you that you would like to be paid",
  description: "Only somebody the group owes in that currency may ask, and only a current member with an account who owes can be asked. One person reminds another at most once a day; a second attempt is answered `already_reminded` with when the first went. Nothing is recorded in the group.",
  request: { params: GroupPathSchema, body: jsonBody(ReminderInputSchema) },
  responses: { 200: jsonResponse(ReminderSchema, "What became of the reminder"), ...refusals },
});

export function ledgerRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(pullRoute, async (c) => {
    const { groups, limit } = c.req.valid("json");
    const viewer = c.var.session.userId;
    const [{ groupIds, seen }, results] = await Promise.all([membershipsOf(c.var.db, viewer), Promise.all(groups.map(({ groupId, since }) => group(c, groupId).changes(viewer, since, limit)))]);

    const pages: GroupChanges[] = [];
    const refused: GroupRefusal[] = [];
    results.forEach((result, index) => {
      if (result.ok) pages.push(result.value);
      else refused.push({ groupId: groups[index]?.groupId ?? "", ...result.error });
    });

    const profilesById = await profilesOf(
      c.var.db,
      pages.flatMap((page) => page.members),
    );
    return c.json(
      {
        groupIds,
        seen,
        pages: pages.map((page) => ({ ...page, profiles: currentProfiles(page.members).flatMap((id) => profilesById.get(id) ?? []) })),
        refusals: refused,
      },
      200,
    );
  });

  routes.openapi(putGroupRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).putGroup(groupId, c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(putMemberRoute, async (c) => {
    const { groupId, memberId } = c.req.valid("param");
    return respond(c, await group(c, groupId).putMember(memberId, c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(putEntryRoute, async (c) => {
    const { groupId, entryId } = c.req.valid("param");
    return respond(c, await group(c, groupId).putEntry(entryId, c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(putSeenRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    const viewer = c.var.session.userId;
    const now = new Date().toISOString();
    // Re-rendered, so every stored value has the same precision and compares as text.
    const sent = new Date(c.req.valid("json").seenAt).toISOString();
    // ISO-8601 in UTC, so the earlier string is the earlier time.
    const seenAt = sent < now ? sent : now;
    const mine = and(eq(memberships.profileId, viewer), eq(memberships.groupId, groupId), isNull(memberships.leftAt));

    await c.var.db
      .update(memberships)
      .set({ seenAt })
      .where(and(mine, or(isNull(memberships.seenAt), lt(memberships.seenAt, seenAt))));
    const row = await c.var.db.select({ seenAt: memberships.seenAt }).from(memberships).where(mine).get();
    if (!row) return c.json(apiError("not_member", "You are not a member of this group.", "permanent"), 403);
    return c.json({ groupId, seenAt: row.seenAt ?? seenAt }, 200);
  });

  routes.openapi(remindRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    const { memberId, currency } = c.req.valid("json");
    const route = await group(c, groupId).reminderRoute(memberId, currency, c.var.session.userId);
    if (!route.ok) return refused(c, route.error);
    const { fromMemberId, toProfileId } = route.value;

    // KV forgets the key by itself after a day. It is eventually consistent,
    // so two taps a moment apart can both send: a brake, not a ledger.
    const key = `reminder:${groupId}:${fromMemberId}:${memberId}`;
    const earlier = await c.env.CACHE.get(key);
    if (earlier !== null) return c.json({ outcome: "already_reminded" as const, sentAt: earlier }, 200);

    const devices = await wakeProfile(c.env, toProfileId, { groupId, eventId: crypto.randomUUID(), kind: "reminder", subjectId: fromMemberId, currency });
    if (devices === 0) return c.json({ outcome: "unreachable" as const, sentAt: null }, 200);

    const sentAt = new Date().toISOString();
    await c.env.CACHE.put(key, sentAt, { expirationTtl: REMINDER_INTERVAL_SECONDS });
    return c.json({ outcome: "sent" as const, sentAt }, 200);
  });
}

/** The groups the account actively participates in, and how far it has read each. */
async function membershipsOf(db: DrizzleD1Database, profileId: string): Promise<{ groupIds: string[]; seen: GroupSeen[] }> {
  const rows = await db
    .select({ groupId: memberships.groupId, seenAt: memberships.seenAt })
    .from(memberships)
    .where(and(eq(memberships.profileId, profileId), isNull(memberships.leftAt)))
    .all();
  return {
    groupIds: rows.map((row) => row.groupId),
    seen: rows.flatMap(({ groupId, seenAt }) => (seenAt === null ? [] : [{ groupId, seenAt }])),
  };
}

/** The accounts holding a page's current places: ids the group named, never ones a client asked for. */
function currentProfiles(members: Member[]): string[] {
  return [...new Set(members.flatMap((member) => (member.profileId !== null && member.leftAt === null ? [member.profileId] : [])))];
}

/** Every profile any page names, read once for the whole pull. */
async function profilesOf(db: DrizzleD1Database, members: Member[]): Promise<Map<string, Profile>> {
  const pages = await Promise.all(chunked(currentProfiles(members)).map((chunk) => db.select().from(profiles).where(inArray(profiles.id, chunk)).all()));
  return new Map(pages.flat().map((profile) => [profile.id, profile]));
}
