import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import { eq } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import type { AppEnv } from "../context";
import { linkTokens, profiles } from "../db/d1/schema";
import { apiError, jsonBody, jsonResponse } from "../schemas/common";
import { GroupLinkSchema, InviteSchema, JoinedSchema, JoinRequestSchema, LinkPreviewSchema, LinkRevocationSchema, LiveLinkSchema, PlaceholderListSchema } from "../schemas/ledger";
import { GroupPathSchema, group, MemberPathSchema, maybeSignedIn, refusals, respond, signedIn, TokenPathSchema } from "./routing";

/**
 * Minting links (a member handing authority out) and spending them (somebody
 * arriving). A token reaches its group through D1's `link_tokens`, which only
 * routes: whether the link is spent, expired or revoked is the object's call.
 */

const createInviteRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "createInvite",
  path: "/groups/{groupId}/members/{memberId}/invite",
  tags: ["invites"],
  summary: "Hand one unclaimed place to one person",
  description: "Reissuing invalidates whatever was sent before.",
  request: { params: MemberPathSchema },
  responses: { 200: jsonResponse(InviteSchema, "The invite"), ...refusals },
});

const createLinkRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "createGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "Mint the group's one open link",
  description: "Whoever holds it may join until it expires or is revoked. Minting revokes the previous one; both are in the activity feed.",
  request: { params: GroupPathSchema },
  responses: { 200: jsonResponse(GroupLinkSchema, "The new live link"), ...refusals },
});

const liveLinkRoute = createRoute({
  ...signedIn,
  method: "get",
  operationId: "getGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "The group's open link, if it has a usable one",
  request: { params: GroupPathSchema },
  responses: { 200: jsonResponse(LiveLinkSchema, "The link, or null"), ...refusals },
});

const revokeLinkRoute = createRoute({
  ...signedIn,
  method: "delete",
  operationId: "revokeGroupLink",
  path: "/groups/{groupId}/link",
  tags: ["invites"],
  summary: "Turn the group's open link off",
  request: { params: GroupPathSchema },
  responses: { 200: jsonResponse(LinkRevocationSchema, "The token that is no longer live, or null"), ...refusals },
});

const peekRoute = createRoute({
  ...maybeSignedIn,
  method: "get",
  operationId: "peekLink",
  path: "/links/{token}",
  tags: ["invites"],
  summary: "What a link is for, without spending it",
  description: "Works with no session. A spent, expired or revoked token still describes itself.",
  request: { params: TokenPathSchema },
  responses: { 200: jsonResponse(LinkPreviewSchema, "What the link names"), 404: refusals[404], 410: refusals[410] },
});

const placeholdersRoute = createRoute({
  ...signedIn,
  method: "get",
  operationId: "linkPlaceholders",
  path: "/links/{token}/placeholders",
  tags: ["invites"],
  summary: "The unclaimed places this link's group is holding",
  description: "Other people's names, so a session is required, unlike the preview.",
  request: { params: TokenPathSchema },
  responses: { 200: jsonResponse(PlaceholderListSchema, "Places nobody has claimed"), ...refusals },
});

const joinRoute = createRoute({
  ...signedIn,
  method: "post",
  operationId: "joinWithLink",
  path: "/links/{token}/join",
  tags: ["invites"],
  summary: "Walk in on a link",
  description: "Claiming a place sets one column on a member row that already has balances; arriving as somebody new inserts one. Never a second place for one account.",
  request: { params: TokenPathSchema, body: jsonBody(JoinRequestSchema) },
  responses: { 200: jsonResponse(JoinedSchema, "The group, and your place in it"), ...refusals },
});

const invalidLink = () => apiError("invite_invalid", "This link is not valid.");

export function inviteRoutes(routes: OpenAPIHono<AppEnv>) {
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

  routes.openapi(peekRoute, async (c) => {
    const { token } = c.req.valid("param");
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) return c.json(invalidLink(), 404);

    const result = await group(c, groupId).peekLink(token, c.var.session?.userId ?? null);
    // The index routed to an object that is gone or never knew the token: still a dead link.
    if (!result.ok) return c.json(apiError(result.error.code, result.error.message), 410);
    if (result.value === null) return c.json(invalidLink(), 404);
    return c.json(result.value, 200);
  });

  routes.openapi(placeholdersRoute, async (c) => {
    const { token } = c.req.valid("param");
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) return c.json(invalidLink(), 404);
    return respond(c, await group(c, groupId).placeholders(token));
  });

  routes.openapi(joinRoute, async (c) => {
    const { token } = c.req.valid("param");
    const viewer = c.var.session.userId;
    const groupId = await groupFor(c.var.db, token);
    if (!groupId) return c.json(invalidLink(), 404);

    /**
     * Names meet here, since the object holds member names and D1 the
     * account's. A newcomer who typed none arrives under their account's name;
     * claiming a placeholder gives its name to an account that has none.
     */
    const request = c.req.valid("json");
    const profile = await c.var.db.select({ displayName: profiles.displayName }).from(profiles).where(eq(profiles.id, viewer)).get();
    const result = await group(c, groupId).join(token, viewer, { ...request, displayName: request.displayName ?? profile?.displayName ?? null });

    if (result.ok && !profile?.displayName) {
      await c.var.db.update(profiles).set({ displayName: result.value.member.displayName, updatedAt: new Date().toISOString() }).where(eq(profiles.id, viewer));
    }
    return respond(c, result);
  });
}

async function groupFor(db: DrizzleD1Database, token: string): Promise<string | null> {
  const row = await db.select({ groupId: linkTokens.groupId }).from(linkTokens).where(eq(linkTokens.token, token)).get();
  return row?.groupId ?? null;
}
