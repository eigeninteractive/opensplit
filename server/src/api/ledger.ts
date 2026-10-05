import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { and, eq, inArray, isNull } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { chunked } from "../chunked";
import type { AppEnv } from "../context";
import { memberships, profiles } from "../db/d1/schema";
import type { Profile } from "../schemas/account";
import { jsonBody, jsonResponse } from "../schemas/common";
import { EntryInputSchema, EntrySchema, type GroupChanges, GroupInputSchema, type GroupRefusal, GroupSchema, type Member, MemberInputSchema, MemberSchema, PullRequestSchema, PullSchema } from "../schemas/ledger";
import { EntryPathSchema, GroupPathSchema, group, MemberPathSchema, refusals, respond, signedIn } from "./routing";

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
  summary: "Make a group and its creator's place in it, or rename, archive or change a setting",
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
  description: "Your own row and any placeholder are editable; another account holder's are not. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.",
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

export function ledgerRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(pullRoute, async (c) => {
    const { groups, limit } = c.req.valid("json");
    const viewer = c.var.session.userId;
    const [groupIds, results] = await Promise.all([groupsOf(c.var.db, viewer), Promise.all(groups.map(({ groupId, since }) => group(c, groupId).changes(viewer, since, limit)))]);

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
}

/** The groups an account is in now, from D1's index of them. */
async function groupsOf(db: DrizzleD1Database, profileId: string): Promise<string[]> {
  const rows = await db
    .select({ groupId: memberships.groupId })
    .from(memberships)
    .where(and(eq(memberships.profileId, profileId), isNull(memberships.leftAt)))
    .all();
  return rows.map((row) => row.groupId);
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
