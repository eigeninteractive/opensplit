import { z } from "@hono/zod-openapi";
import type { Context } from "hono";

import { requireSession, withSession } from "../context";
import { kindOf, type Result, statusFor } from "../do/group/refusal";
import { apiError, errorResponse, IdSchema } from "../schemas/common";

/** What every route module shares: session guards, addressing, and how a refusal becomes a response. */

type Security = Record<string, string[]>[];

/** A bearer token on Android, the HttpOnly session cookie on the web. */
const session: Security = [{ bearer: [] }, { cookie: [] }];

/** Spread into a route that requires a session. */
export const signedIn = { middleware: requireSession, security: session };

/** Spread into a route that reads the session when there is one. */
export const maybeSignedIn = { middleware: withSession, security: [{}, ...session] as Security };

/** Coerced, because a query parameter is a string. */
export const SeqQuerySchema = z.coerce.number().int().nonnegative().openapi({ type: "integer", example: 412 });

/** Coercion turns null into 0, so the generator would call it optional; state it. */
export const RequiredSeqQuerySchema = SeqQuerySchema.openapi({ param: { required: true } });

export const GroupPathSchema = z.object({
  groupId: IdSchema.openapi({ param: { name: "groupId", in: "path" } }),
});

export const EntryPathSchema = GroupPathSchema.extend({
  entryId: IdSchema.openapi({ param: { name: "entryId", in: "path" } }),
});

export const MemberPathSchema = GroupPathSchema.extend({
  memberId: IdSchema.openapi({ param: { name: "memberId", in: "path" } }),
});

export const TokenPathSchema = z.object({
  token: IdSchema.openapi({ param: { name: "token", in: "path" } }),
});

/**
 * Every refusal a group object can give, on every route that reaches one. Not
 * `as const`: zod-openapi cannot read readonly responses when typing a handler.
 */
export const refusals = {
  400: errorResponse("The request is malformed."),
  401: errorResponse("No session."),
  403: errorResponse("You are not a member of this group, or not allowed to change that."),
  404: errorResponse("No such group, entry, member or link."),
  409: errorResponse("The request conflicts with the group's current state. Read `error.retry` before retrying."),
  410: errorResponse("The group was collected, or the link has expired."),
  422: errorResponse("The expense does not add up."),
};

type WorkerEnv = { Bindings: Env };

export function respond<T extends object, E extends WorkerEnv>(c: Context<E>, result: Result<T>) {
  if (result.ok) return c.json(result.value, 200);
  const { code, message } = result.error;
  return c.json(apiError(code, message, kindOf(code)), statusFor(code));
}

/** The group's object, addressed by the id the client minted. */
export function group<E extends WorkerEnv>(c: Context<E>, groupId: string) {
  return c.env.GROUP.getByName(groupId);
}
