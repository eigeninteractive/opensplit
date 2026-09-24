import { createRoute, OpenAPIHono } from "@hono/zod-openapi";
import { eq } from "drizzle-orm";

import { type AppEnv, type AuthedEnv, withSession } from "../context";
import { linkTokens, profiles } from "../db/d1/schema";
import type { Result } from "../do/group/refusal";
import { apiError, jsonResponse } from "../schemas/common";
import { InviteSchema, JoinedSchema, JoinRequestSchema, LinkPreviewSchema, LinkRevocationSchema, LiveLinkSchema, MintedLinkSchema, PlaceholderListSchema } from "../schemas/ledger";
import { GroupPathSchema, group, MemberPathSchema, refusals, respond, TokenPathSchema } from "./routing";

/**
 * Getting into a group: minting links, and spending them.
 *
 * Split down the middle by one question — do we know who is asking?
 *
 * Everything under `/groups/{groupId}` is a member handing authority *out*,
 * and the group's Durable Object refuses anybody who is not in it. Everything
 * under `/links/{token}` is somebody arriving, and the first of those runs with
 * no session at all, because at that moment the caller is by design nobody yet.
 *
 * ## Why a token routes through D1
 *
 * A group's object is addressed by its group id, and whoever tapped a link does
 * not have one — that is the whole point of an invite. `link_tokens` in D1 is
 * the smallest thing that can bridge it: a token, and the group whose object
 * knows what the token actually means.
 *
 * It deliberately carries no state about whether the link is spent, expired or
 * revoked, so a stale row here cannot let anybody in. It routes; the object
 * decides. What a stale row *can* do is route a token that has been superseded,
 * which is why minting one stages a delete of the links it replaced.
 */

const createInviteRoute = createRoute({
  method: "post",
  operationId: "createInvite",
  path: "/groups/{groupId}/members/{memberId}/invite",
  tags: ["invites"],
  summary: "Hand one unclaimed place to one person",
  description: "Only for a place nobody has claimed: handing out a link to a member who already has an account would be an account takeover with extra steps. Reissuing invalidates whatever was sent before, so an old link found in a chat history cannot still be spent.",
  request: { params: MemberPathSchema },
  responses: { 200: jsonResponse(InviteSchema, "The invite, and the links it replaced"), ...refusals },
});

const createLinkRoute = createRoute({
  method: "post",
  operationId: "createGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "Mint the group's one open link",
  description:
    "Bearer authority over membership: whoever holds it may join, any number of times, until it expires or is revoked. One live link at a time — minting revokes the previous one — and both the minting and the revocation are written to the activity feed, because a group that cannot see its open door has no way to decide it should be shut.",
  responses: { 200: jsonResponse(MintedLinkSchema, "The link, and the one it replaced"), ...refusals },
  request: { params: GroupPathSchema },
});

const liveLinkRoute = createRoute({
  method: "get",
  operationId: "getGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "The group's open link, if it has a usable one",
  description: "Null when nobody has minted one, or the last one has expired or been revoked. Requires membership, because it hands a working URL out rather than describing one somebody already holds.",
  request: { params: GroupPathSchema },
  responses: { 200: jsonResponse(LiveLinkSchema, "The link, or null"), ...refusals },
});

const revokeLinkRoute = createRoute({
  method: "delete",
  operationId: "revokeGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "Turn the group's open link off",
  request: { params: GroupPathSchema },
  responses: { 200: jsonResponse(LinkRevocationSchema, "The token that is no longer live, or null"), ...refusals },
});

const peekRoute = createRoute({
  method: "get",
  operationId: "peekLink",
  path: "/{token}",
  tags: ["invites"],
  summary: "What a link is for, without spending it",
  description: "Works with no session, which is the point: whoever just tapped the link has not been asked who they are yet. A spent, expired or revoked token still describes itself, so a screen can say which of those it is rather than showing 'invalid link' for three different reasons.",
  request: { params: TokenPathSchema },
  responses: {
    200: jsonResponse(LinkPreviewSchema, "What the link names"),
    404: refusals[404],
    410: refusals[410],
  },
});

const placeholdersRoute = createRoute({
  method: "get",
  operationId: "linkPlaceholders",
  path: "/{token}/placeholders",
  tags: ["invites"],
  summary: "The unclaimed places this link's group is holding",
  description: "Requires a session, unlike the preview: these are other people's names, which is more than the link implies to whoever holds it. It is asked after the arrival has chosen an account rather than before, which they have to do to join in any case.",
  request: { params: TokenPathSchema },
  responses: { 200: jsonResponse(PlaceholderListSchema, "Places nobody has claimed"), ...refusals },
});

const joinRoute = createRoute({
  method: "post",
  operationId: "joinWithLink",
  path: "/{token}/join",
  tags: ["invites"],
  summary: "Walk in on a link",
  description: "Claiming a place sets exactly one column on a member row that already has balances and history; arriving as somebody new inserts one. Never both, and never a second place for one account.",
  request: { params: TokenPathSchema, body: { required: true, content: { "application/json": { schema: JoinRequestSchema } } } },
  responses: { 200: jsonResponse(JoinedSchema, "The group, and your place in it"), ...refusals },
});

/** The half that requires membership: handing authority out. See `app.ts`. */
export function inviteRoutes(routes: OpenAPIHono<AuthedEnv>) {
  routes.openapi(createInviteRoute, async (c) => {
    const { groupId, memberId } = c.req.valid("param");
    return respond(c, await group(c, groupId).createInvite(memberId, c.var.session.userId));
  });

  routes.openapi(createLinkRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).createLink(c.var.session.userId));
  });

  routes.openapi(liveLinkRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).liveLink(c.var.session.userId));
  });

  routes.openapi(revokeLinkRoute, async (c) => {
    const { groupId } = c.req.valid("param");
    return respond(c, await group(c, groupId).revokeLink(c.var.session.userId));
  });
}

/**
 * The half that is somebody arriving, mounted at `/api/links`.
 *
 * Its own app, with `withSession` rather than `requireSession`, because the
 * preview has to answer a caller who has not decided who they are — and the
 * two that do need a session say so themselves, inline, rather than the whole
 * family being gated on the strictest of the three.
 *
 * That ordering is not a preference. Redeeming first and asking afterwards is
 * the bug this app already shipped: somebody who already had an account tapped
 * a friend's invite, the slot was claimed by the throwaway guest that happened
 * to hold the session, the single-use token was spent, and the only repair was
 * the group's owner issuing a fresh link.
 */
export function linkRoutes() {
  const routes = new OpenAPIHono<AppEnv>({
    defaultHook: (result, c) => {
      if (result.success) return;
      return c.json(apiError("malformed", result.error.issues[0]?.message ?? "Invalid.", "permanent"), 400);
    },
  });

  routes.use("*", withSession);

  routes.openapi(peekRoute, async (c) => {
    const { token } = c.req.valid("param");
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) {
      return c.json(apiError("invite_invalid", "This link is not valid.", "permanent"), 404);
    }

    const viewer = c.var.session?.userId ?? null;
    const result = await group(c, groupId).peekLink(token, viewer);

    // The object is gone, or never knew this token. The index said otherwise,
    // which is exactly the staleness it is allowed to have: it routes, and
    // being routed somewhere that cannot answer is still a dead link.
    if (!result.ok) {
      return c.json(apiError(result.error.code, result.error.message, "permanent"), 410);
    }
    if (result.value === null) {
      return c.json(apiError("invite_invalid", "This link is not valid.", "permanent"), 404);
    }

    return c.json(result.value, 200);
  });

  routes.openapi(placeholdersRoute, async (c) => {
    const viewer = c.var.session?.userId;
    if (!viewer) return c.json(apiError("no_session", "Sign in first."), 401);

    const { token } = c.req.valid("param");
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) return c.json(apiError("invite_invalid", "This link is not valid.", "permanent"), 404);

    return respond(
      c,
      mapped(await group(c, groupId).placeholders(token, viewer), (rows) => ({ placeholders: rows })),
    );
  });

  routes.openapi(joinRoute, async (c) => {
    const viewer = c.var.session?.userId;
    if (!viewer) return c.json(apiError("no_session", "Sign in first."), 401);

    const { token } = c.req.valid("param");
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) return c.json(apiError("invite_invalid", "This link is not valid.", "permanent"), 404);

    /**
     * The name travels both ways here, and this is the only place it can.
     *
     * A group's object holds member names; D1 holds the account's own. Neither
     * can see the other, so the two halves of "what are you called" meet in
     * this handler:
     *
     * *Inwards*, somebody arriving as a new member who did not type a name
     * gets the one already on their account, which is what anybody who signed
     * in with Google or an email address will have.
     *
     * *Outwards*, claiming a place adopts the name a friend typed on the
     * placeholder — but only into a profile that has none. That "only" is the
     * whole check: it is what stops a name somebody actually chose being
     * overwritten by a friend's guess, and it is why `profiles.display_name`
     * is null for a guest rather than carrying the anonymous plugin's
     * invention. See `auth.ts`.
     */
    const { memberId, displayName } = c.req.valid("json");
    const profile = await c.var.db.select({ displayName: profiles.displayName }).from(profiles).where(eq(profiles.id, viewer)).get();

    const result = await group(c, groupId).join(token, viewer, { memberId, displayName: displayName ?? profile?.displayName ?? null });

    if (result.ok && !profile?.displayName) {
      await c.var.db.update(profiles).set({ displayName: result.value.displayName, updatedAt: new Date().toISOString() }).where(eq(profiles.id, viewer));
    }

    return respond(
      c,
      mapped(result, (member) => ({ groupId, member })),
    );
  });

  return routes;
}

/**
 * A refusal passes through; a value is reshaped.
 *
 * Wrapping an array in an object is the one thing several handlers here do
 * between the object's answer and the wire, and doing it by hand means
 * re-deriving the refusal branch each time — which is where a status quietly
 * becomes a 500.
 */
function mapped<T, U extends object>(result: Result<T>, shape: (value: T) => U): Result<U> {
  return result.ok ? { ok: true, value: shape(result.value) } : result;
}

/**
 * Which group a token is for, or null.
 *
 * The one read that has to happen before a Durable Object can be addressed at
 * all, and the only place in the API where D1 answers a question about a group
 * rather than about an account.
 */
async function groupFor(db: AppEnv["Variables"]["db"], token: string): Promise<string | null> {
  const row = await db.select({ groupId: linkTokens.groupId }).from(linkTokens).where(eq(linkTokens.token, token)).get();
  return row?.groupId ?? null;
}
