import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq, isNull } from "drizzle-orm";
import type { Context } from "hono";

import { type AuthedEnv, requireSession } from "../context";
import { memberships, profiles } from "../db/d1/schema";
import { kindOf, type Result, statusFor } from "../do/group/refusal";
import { apiError, errorResponse, IdSchema, jsonResponse } from "../schemas/common";
import { ChangePageSchema, EntryInputSchema, EntrySchema, GroupCreateSchema, GroupPatchSchema, GroupSchema, MemberCreateSchema, MemberPatchSchema, MemberSchema } from "../schemas/ledger";

/**
 * The sync surface: one request per group, one integer cursor.
 *
 * These handlers are deliberately thin, and that is the point of the phase
 * before this one. Every rule about who may do what lives in the group's
 * Durable Object, which is the only thing that can answer it without a race;
 * every rule about *shape* lives in the Zod schemas, which answer it before a
 * Durable Object is woken at all. What is left here is routing and the
 * translation of one refusal vocabulary into another.
 *
 * ## There is no membership check here
 *
 * The plan called for one: read D1's `memberships` index first, refuse cheap,
 * and only then wake the object. Building it, the saving turned out not to be
 * there and the cost was real.
 *
 * The saving is not there because a D1 read is a subrequest too — roughly what
 * asking the object costs — and because the object answers `not_member` from
 * its own table in microseconds. The cost is that the index is *derived*: it
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
 * A sequence number arriving in a query string.
 *
 * Coerced, because a query parameter is a string and `SeqSchema` is an
 * integer: without this every `?since=0` is a 400 that parses as an empty
 * page, which is exactly as confusing to debug as it sounds. Path and body
 * fields are not coerced — JSON already has numbers, and silently accepting
 * `"1000"` as an amount is not a kindness.
 */
const SeqQuerySchema = z.coerce.number().int().nonnegative().openapi({ type: "integer", example: 412 });

const GroupPathSchema = z.object({
  groupId: IdSchema.openapi({ param: { name: "groupId", in: "path" } }),
});

const EntryPathSchema = GroupPathSchema.extend({
  entryId: IdSchema.openapi({ param: { name: "entryId", in: "path" } }),
});

const MemberPathSchema = GroupPathSchema.extend({
  memberId: IdSchema.openapi({ param: { name: "memberId", in: "path" } }),
});

/**
 * Every refusal the Durable Object can give, on every route that can reach it.
 *
 * Spread wholesale rather than picked per route, and that is honest rather
 * than lazy: the object decides, the handler cannot know which subset applies,
 * and a route that documented four of the six would be documenting a guess.
 *
 * Deliberately not `as const`. `@hono/zod-openapi` builds a handler's allowed
 * return type from the `responses` it can read, and `readonly` properties are
 * not among them — so with `as const` every error status vanished from the
 * union and returning one was a type error against the 200 alone. The failure
 * reads as "your refusal is missing fourteen properties of Group", which is a
 * long way from "this object is frozen".
 */
const refusals = {
  400: errorResponse("The request is malformed."),
  401: errorResponse("No session."),
  403: errorResponse("You are not a member of this group, or not allowed to change that."),
  404: errorResponse("No such group, entry or member."),
  409: errorResponse("The request conflicts with the group's current state. Read `error.retry` before retrying."),
  410: errorResponse("The group was collected, or the link has expired."),
  422: errorResponse("The expense does not add up."),
};

type RefusalStatus = 400 | 401 | 403 | 404 | 409 | 410 | 422;

/**
 * One refusal vocabulary translated into another, in one place.
 *
 * The object speaks in codes because a code is the thing that survives being
 * read by a client. This adds the status, which is what makes the response an
 * HTTP response, and the retry kind, which is what the device acts on — see
 * `ErrorSchema`. None of the three is derived from the others.
 */
function respond<T extends object>(c: Context<AuthedEnv>, result: Result<T>) {
  if (result.ok) return c.json(result.value, 200);

  const { code, message } = result.error;
  return c.json(apiError(code, message, kindOf(code)), statusFor(code) as RefusalStatus);
}

/** The group's object, addressed by the id the client minted for it. */
function group(c: Context<AuthedEnv>, groupId: string) {
  return c.env.GROUP.getByName(groupId);
}

/**
 * What a device needs before it can sync anything: who it is, and which groups
 * to ask.
 *
 * The only thing here that cannot come from a group's object, because it is
 * the question no single group can answer. Postgres answered it with a join
 * across `members`; the object model answers it with the derived index, which
 * is the reason that index exists.
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
  path: "/bootstrap",
  tags: ["sync"],
  summary: "Who I am, and which groups to ask",
  responses: { 200: jsonResponse(BootstrapSchema, "The account and its groups"), 401: refusals[401] },
});

const changesRoute = createRoute({
  method: "get",
  path: "/groups/{groupId}/changes",
  tags: ["sync"],
  summary: "Everything that changed in one group since a cursor",
  description: "`limit` counts changes, not rows. Every row written by one call shares a sequence number and a page is only ever cut between numbers, so a device sees a whole write or none of it — it can never observe an expense whose shares have not arrived. Send `seq` back as `since` next time.",
  request: { params: GroupPathSchema, query: z.object({ since: SeqQuerySchema.default(0), limit: z.coerce.number().int().min(1).max(500).default(200).openapi({ type: "integer", example: 200 }) }) },
  responses: { 200: jsonResponse(ChangePageSchema, "The page, and the cursor to send next time"), ...refusals },
});

const createGroupRoute = createRoute({
  method: "post",
  path: "/groups",
  tags: ["groups"],
  summary: "Make a group, and its creator's place in it",
  description: "Idempotent for the account that made it, so a retry whose response was lost returns the same group rather than refusing.",
  request: { body: { required: true, content: { "application/json": { schema: GroupCreateSchema } } } },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const patchGroupRoute = createRoute({
  method: "patch",
  path: "/groups/{groupId}",
  tags: ["groups"],
  summary: "Rename, archive or change a setting",
  description: "A patch, not a whole row. There are no fields for `id`, `createdAt` or `createdBy`, which is why nothing needs to forbid rewriting them.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: GroupPatchSchema } } } },
  responses: { 200: jsonResponse(GroupSchema, "The group"), ...refusals },
});

const addMemberRoute = createRoute({
  method: "post",
  path: "/groups/{groupId}/members",
  tags: ["groups"],
  summary: "Add somebody who has never opened the app",
  description: "A placeholder is a full member: they can pay, hold a balance and be settled with. Claiming an invite later sets one column and moves no money.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: MemberCreateSchema } } } },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const patchMemberRoute = createRoute({
  method: "patch",
  path: "/groups/{groupId}/members/{memberId}",
  tags: ["groups"],
  summary: "Change a name, a payment handle, or whether somebody is still here",
  description: "Your own row and any placeholder are editable; another account holder's are not — including by whoever made the group. Leaving is always yours to do; removing somebody else requires them to be settled in every currency.",
  request: { params: MemberPathSchema, body: { required: true, content: { "application/json": { schema: MemberPatchSchema } } } },
  responses: { 200: jsonResponse(MemberSchema, "The member"), ...refusals },
});

const upsertEntryRoute = createRoute({
  method: "post",
  path: "/groups/{groupId}/entries",
  tags: ["entries"],
  summary: "Record or edit an expense, whole",
  description: "Whole rather than by column: an amount, its payers and its shares are one coherent fact. Send `baseSeq` to be told when somebody else has moved the money since you composed the edit — a stale base is refused only when applying the write would move money, so two people fixing a typo never arbitrate.",
  request: { params: GroupPathSchema, body: { required: true, content: { "application/json": { schema: EntryInputSchema } } } },
  responses: { 200: jsonResponse(EntrySchema, "The expense as stored"), ...refusals },
});

const deleteEntryRoute = createRoute({
  method: "delete",
  path: "/groups/{groupId}/entries/{entryId}",
  tags: ["entries"],
  summary: "Soft-delete an expense",
  description: "Deleting always moves money, so unlike a prose edit it must carry the exact version the device last saw. The row stays in the feed with `deletedAt` set; nothing here can remove it.",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: SeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, now deleted"), ...refusals },
});

const restoreEntryRoute = createRoute({
  method: "post",
  path: "/groups/{groupId}/entries/{entryId}/restore",
  tags: ["entries"],
  summary: "Put a deleted expense back",
  request: { params: EntryPathSchema, query: z.object({ baseSeq: SeqQuerySchema }) },
  responses: { 200: jsonResponse(EntrySchema, "The expense, restored"), ...refusals },
});

export function ledgerRoutes() {
  const routes = new OpenAPIHono<AuthedEnv>({
    defaultHook: (result, c) => {
      if (result.success) return;
      return c.json(apiError("malformed", result.error.issues[0]?.message ?? "Invalid.", "permanent"), 400);
    },
  });

  /**
   * Named path families rather than `use("*")`.
   *
   * This sub-app is mounted at `/api`, so a wildcard here claims every path
   * under it — including ones it does not own. `/api/nope` then answers 401
   * instead of 404, which is both wrong and inconsistent with `/api/health`
   * and `/api/auth/*` sitting unauthenticated beside it. Naming the two
   * families it actually owns keeps the refusal where it belongs.
   */
  routes.use("/bootstrap", requireSession);
  routes.use("/groups", requireSession);
  routes.use("/groups/*", requireSession);

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

  return routes;
}
