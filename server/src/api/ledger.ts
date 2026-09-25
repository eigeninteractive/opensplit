import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";

import type { AuthedEnv } from "../context";
import { memberships, profiles } from "../db/d1/schema";
import { IdSchema, jsonResponse } from "../schemas/common";
import { ChangePageSchema, EntryInputSchema, EntrySchema, GroupCreateSchema, GroupPatchSchema, GroupSchema, MemberCreateSchema, MemberPatchSchema, MemberSchema } from "../schemas/ledger";
import { EntryPathSchema, GroupPathSchema, group, MemberPathSchema, refusals, respond, SeqQuerySchema } from "./routing";

/**
 * The sync surface: one request per group, one integer cursor.
 *
 * These handlers are deliberately thin. Every rule about who may do what lives in the group's
 * Durable Object, which is the only thing that can answer it without a race;
 * every rule about *shape* lives in the Zod schemas, which answer it before a
 * Durable Object is woken at all. What is left here is routing and the
 * translation of one refusal vocabulary into another.
 *
 * ## There is no membership check here
 *
 * Reading D1's `memberships` index first to refuse cheaply saves nothing: a D1
 * read is a subrequest too, roughly what asking the object costs, and the
 * object answers `not_member` from its own table in microseconds. It would
 * cost something, though: the index is *derived*: it
 * lags by however long the outbox takes to flush. The window is normally
 * nothing, but it opens exactly where it hurts most, which is the moment
 * somebody joins: the object has them as a member, D1 does not yet, and every
 * request they make would be refused until an alarm caught up.
 *
 * So `memberships` keeps the job it is genuinely for — answering "which groups
 * am I in", which no single object can — and stops being an authorization.
 * The object was always the authority; now it is also the only one asked.
 */

/**
 * What a device needs before it can sync anything: who it is, and which groups
 * to ask.
 *
 * The only thing here that cannot come from a group's object, because it is
 * the question no single group can answer: a group knows who is in it, and
 * nothing asks a hundred groups whether they contain you. The derived index in
 * D1 answers it instead, which is the reason that index exists at all.
 */
const BootstrapSchema = z
  .object({
    profileId: IdSchema,
    displayName: z.string().nullable(),
    upiVpa: z.string().nullable(),
    isAnonymous: z.boolean(),

    /** Groups this account is still in. A group left is a group not listed. */
    groupIds: z.array(IdSchema),
  })
  .openapi("Bootstrap");

export type Bootstrap = z.infer<typeof BootstrapSchema>;

const bootstrapRoute = createRoute({
  method: "get",
  operationId: "bootstrap",
  path: "/bootstrap",
  tags: ["sync"],
  summary: "Who I am, and which groups to ask",
  responses: { 200: jsonResponse(BootstrapSchema, "The account and its groups"), 401: refusals[401] },
});

const changesRoute = createRoute({
  method: "get",
  operationId: "getChanges",
  path: "/groups/{groupId}/changes",
  tags: ["sync"],
  summary: "Everything that changed in one group since a cursor",
  description: "`limit` counts changes, not rows. Every row written by one call shares a sequence number and a page is only ever cut between numbers, so a device sees a whole write or none of it — it can never observe an expense whose shares have not arrived. Send `seq` back as `since` next time.",
  request: { params: GroupPathSchema, query: z.object({ since: SeqQuerySchema.default(0), limit: z.coerce.number().int().min(1).max(500).default(200).openapi({ type: "integer", example: 200 }) }) },
  responses: { 200: jsonResponse(ChangePageSchema, "The page, and the cursor to send next time"), ...refusals },
});

const createGroupRoute = createRoute({
  method: "post",
  operationId: "createGroup",
  path: "/groups",
  tags: ["groups"],
  summary: "Make a group, and its creator's place in it",
  description: "Idempotent for the account that made it, so a retry whose response was lost returns the same group rather than refusing.",
  request: { body: { required: true, content: { "application/json": { schema: GroupCreateSchema } } } },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const patchGroupRoute = createRoute({
  method: "patch",
  operationId: "updateGroup",
  path: "/groups/{groupId}",
  tags: ["groups"],
  summary: "Rename, archive or change a setting",
  description: "A patch, not a whole row. There are no fields for `id`, `createdAt` or `createdBy`, which is why nothing needs to forbid rewriting them.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: GroupPatchSchema } } } },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const addMemberRoute = createRoute({
  method: "post",
  operationId: "addMember",
  path: "/groups/{groupId}/members",
  tags: ["groups"],
  summary: "Add somebody who has never opened the app",
  description: "A placeholder is a full member: they can pay, hold a balance and be settled with. Claiming an invite later sets one column and moves no money.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: MemberCreateSchema } } } },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const patchMemberRoute = createRoute({
  method: "patch",
  operationId: "updateMember",
  path: "/groups/{groupId}/members/{memberId}",
  tags: ["groups"],
  summary: "Change a name, a payment handle, or whether somebody is still here",
  description: "Your own row and any placeholder are editable; another account holder's are not — including by whoever made the group. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.",
  request: { params: MemberPathSchema, body: { required: true, content: { "application/json": { schema: MemberPatchSchema } } } },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const upsertEntryRoute = createRoute({
  method: "post",
  operationId: "upsertEntry",
  path: "/groups/{groupId}/entries",
  tags: ["entries"],
  summary: "Record or edit an expense, whole",
  description: "Whole rather than by column: an amount, its payers and its shares are one coherent fact. Send `baseSeq` to be told when somebody else has moved the money since you composed the edit — a stale base is refused only when applying the write would move money, so two people fixing a typo never arbitrate.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: EntryInputSchema } } } },
  responses: { 200: jsonResponse(EntrySchema, "The expense as stored"), ...refusals },
});

const deleteEntryRoute = createRoute({
  method: "delete",
  operationId: "deleteEntry",
  path: "/groups/{groupId}/entries/{entryId}",
  tags: ["entries"],
  summary: "Soft-delete an expense",
  description: "Deleting always moves money, so unlike a prose edit it must carry the exact version the device last saw. The row stays in the feed with `deletedAt` set; nothing here can remove it.",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: SeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, now deleted"), ...refusals },
});

const restoreEntryRoute = createRoute({
  method: "post",
  operationId: "restoreEntry",
  path: "/groups/{groupId}/entries/{entryId}/restore",
  tags: ["entries"],
  summary: "Put a deleted expense back",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: SeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, restored"), ...refusals },
});

/**
 * Registers the sync surface onto the app that already requires a session.
 *
 * Takes the app rather than building one, which is what keeps a request to one
 * session read. A sub-app mounted at `/api` carries its own `use()` entries up
 * to the parent as `/api/...` patterns, so two sub-apps each guarding
 * `/groups/*` would resolve the session twice for every ledger request — two
 * D1 reads to answer the same question. Where the boundary is drawn is an
 * app-level fact, so `app.ts` draws it, once, for every module here.
 */
export function ledgerRoutes(routes: OpenAPIHono<AuthedEnv>) {
  routes.openapi(bootstrapRoute, async (c) => {
    const { userId, isAnonymous } = c.var.session;

    const [profile, rows] = await Promise.all([
      c.var.db.select().from(profiles).where(eq(profiles.id, userId)).get(),
      c.var.db
        .select({ groupId: memberships.groupId })
        .from(memberships)
        .where(and(eq(memberships.profileId, userId), isNull(memberships.leftAt)))
        .all(),
    ]);

    return c.json(
      {
        profileId: userId,
        displayName: profile?.displayName ?? null,
        upiVpa: profile?.upiVpa ?? null,
        isAnonymous,
        groupIds: rows.map((row) => row.groupId),
      },
      200,
    );
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

  routes.openapi(patchGroupRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).update(c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(addMemberRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).addMember(c.req.valid("json"), c.var.session.userId));
  });

  routes.openapi(patchMemberRoute, async (c) => {
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
