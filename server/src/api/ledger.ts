import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import type { AppEnv } from "../context";
import { memberships } from "../db/d1/schema";
import { GroupIdsSchema } from "../schemas/account";
import { jsonBody, jsonResponse } from "../schemas/common";
import { ChangePageSchema, EntryInputSchema, EntrySchema, GroupCreateSchema, GroupSchema, GroupUpdateSchema, MemberCreateSchema, MemberSchema, MemberUpdateSchema } from "../schemas/ledger";
import { EntryPathSchema, GroupPathSchema, group, MemberPathSchema, RequiredSeqQuerySchema, refusals, respond, SeqQuerySchema, signedIn } from "./routing";

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

const createGroupRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "createGroup",
  path: "/groups",
  tags: ["groups"],
  summary: "Make a group, and its creator's place in it",
  description: "Idempotent for its creator, so a retry whose response was lost returns the same group.",
  request: { body: jsonBody(GroupCreateSchema) },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const updateGroupRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "updateGroup",
  path: "/groups/{groupId}",
  tags: ["groups"],
  summary: "Rename, archive or change a setting",
  request: { params: GroupPathSchema, body: jsonBody(GroupUpdateSchema) },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const addMemberRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "addMember",
  path: "/groups/{groupId}/members",
  tags: ["groups"],
  summary: "Add somebody who has never opened the app",
  request: { params: GroupPathSchema, body: jsonBody(MemberCreateSchema) },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const updateMemberRoute = createRoute({
  ...signedIn,
  method: "put",
  operationId: "updateMember",
  path: "/groups/{groupId}/members/{memberId}",
  tags: ["groups"],
  summary: "Change a name, a payment handle, or whether somebody is still here",
  description: "Your own row and any placeholder are editable; another account holder's are not. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.",
  request: { params: MemberPathSchema, body: jsonBody(MemberUpdateSchema) },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const upsertEntryRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "upsertEntry",
  path: "/groups/{groupId}/entries",
  tags: ["entries"],
  summary: "Record or edit an expense, whole",
  description: "A stale `baseSeq` is refused only when the write would move money, so two people fixing a typo never arbitrate.",
  request: { params: GroupPathSchema, body: jsonBody(EntryInputSchema) },
  responses: { 200: jsonResponse(EntrySchema, "The expense as stored"), ...refusals },
});

const deleteEntryRoute = createRoute({
  ...signedIn,
  method: "delete",
  operationId: "deleteEntry",
  path: "/groups/{groupId}/entries/{entryId}",
  tags: ["entries"],
  summary: "Soft-delete an expense",
  description: "Deleting always moves money, so it must carry the exact version the device last saw.",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: RequiredSeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, now deleted"), ...refusals },
});

const restoreEntryRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "restoreEntry",
  path: "/groups/{groupId}/entries/{entryId}/restore",
  tags: ["entries"],
  summary: "Put a deleted expense back",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: RequiredSeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, restored"), ...refusals },
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
    return respond(c, await group(c, groupId).changes(c.var.session.userId, since, limit));
  });

  routes.openapi(createGroupRoute, async (c) => {
    const input = c.req.valid("json");
    return respond(c, await group(c, input.id).create(input, c.var.session.userId));
  });

  routes.openapi(updateGroupRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).update(c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(addMemberRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).addMember(c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(updateMemberRoute, async (c) => {
    const { groupId, memberId } = c.req.valid("param");
    return respond(c, await group(c, groupId).updateMember(memberId, c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(upsertEntryRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).upsertEntry(c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(deleteEntryRoute, async (c) => {
    const { groupId, entryId } = c.req.valid("param");
    return respond(c, await group(c, groupId).deleteEntry(entryId, c.req.valid("query").baseSeq, c.var.session.userId));
  });

  routes.openapi(restoreEntryRoute, async (c) => {
    const { groupId, entryId } = c.req.valid("param");
    return respond(c, await group(c, groupId).restoreEntry(entryId, c.req.valid("query").baseSeq, c.var.session.userId));
  });
}
