import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, inArray, isNull } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import { chunked } from "../chunked";
import type { AppEnv } from "../context";
import { memberships, profiles } from "../db/d1/schema";
import { GroupIdsSchema } from "../schemas/account";
import { jsonBody, jsonResponse } from "../schemas/common";
import { ChangePageSchema, EntryInputSchema, EntrySchema, GroupInputSchema, GroupSchema, type Member, MemberInputSchema, MemberSchema } from "../schemas/ledger";
import { EntryPathSchema, GroupPathSchema, group, MemberPathSchema, refusals, refused, respond, SeqQuerySchema, signedIn } from "./routing";

/**
 * The sync surface. Handlers only route: rules about shape are the Zod
 * schemas', rules about who may do what are the group object's. There is no
 * D1 membership check first, because the index lags a join and the object
 * answers `not_member` itself.
 */

const listGroupsRoute = createRoute({
  ...signedIn,
  method: "get",
  operationId: "listGroups",
  path: "/groups",
  tags: ["sync"],
  summary: "The groups this account is still in",
  responses: { 200: jsonResponse(GroupIdsSchema, "The group ids"), 401: refusals[401] },
});

const changesRoute = createRoute({
  ...signedIn,
  method: "get",
  operationId: "getChanges",
  path: "/groups/{groupId}/changes",
  tags: ["sync"],
  summary: "Everything that changed in one group since a cursor",
  description: "`limit` counts changes, not rows, and a page is cut only between sequence numbers, so a device sees a whole write or none of it. Send `seq` back as `since` next time.",
  request: {
    params: GroupPathSchema,
    query: z.object({
      since: SeqQuerySchema.default(0),
      limit: z.coerce.number().int().min(1).max(500).default(200).openapi({ type: "integer", example: 200 }),
    }),
  },
  responses: { 200: jsonResponse(ChangePageSchema, "The page, and the cursor to send next time"), ...refusals },
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
  description: "A stale `baseSeq` is refused only when the write would move money, so two people fixing a typo never arbitrate. Deleting and restoring always move money.",
  request: { params: EntryPathSchema, body: jsonBody(EntryInputSchema) },
  responses: { 200: jsonResponse(EntrySchema, "The expense as stored"), ...refusals },
});

export function ledgerRoutes(routes: OpenAPIHono<AppEnv>) {
  routes.openapi(listGroupsRoute, async (c) => {
    const rows = await c.var.db
      .select({ groupId: memberships.groupId })
      .from(memberships)
      .where(and(eq(memberships.profileId, c.var.session.userId), isNull(memberships.leftAt)))
      .all();
    return c.json({ groupIds: rows.map((row) => row.groupId) }, 200);
  });

  routes.openapi(changesRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    const { since, limit } = c.req.valid("query");
    const result = await group(c, groupId).changes(c.var.session.userId, since, limit);
    if (!result.ok) return refused(c, result.error);
    return c.json({ ...result.value, profiles: await profilesOf(c.var.db, result.value.members) }, 200);
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

/** The accounts holding the page's current places: ids the group named, never ones a client asked for. */
async function profilesOf(db: DrizzleD1Database, members: Member[]) {
  const ids = [...new Set(members.flatMap((member) => (member.profileId !== null && member.leftAt === null ? [member.profileId] : [])))];
  const pages = await Promise.all(chunked(ids).map((chunk) => db.select().from(profiles).where(inArray(profiles.id, chunk)).all()));
  return pages.flat();
}
