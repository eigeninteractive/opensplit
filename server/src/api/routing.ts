import { z } from "@hono/zod-openapi";
import type { Context } from "hono";

import { kindOf, type Result, statusFor } from "../do/group/refusal";
import { apiError, errorResponse, IdSchema } from "../schemas/common";

/**
 * What every route module here shares: how to address a group, and how a
 * refusal becomes an HTTP response.
 *
 * Extracted rather than duplicated because the alternative is three copies of
 * the refusal table, which is the one thing in this layer that must be
 * identical everywhere — a route that documented four of the seven statuses
 * would be documenting a guess, and one that forgot the retry kind would hand
 * the device a "no" it does not know what to do with.
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
export const SeqQuerySchema = z.coerce.number().int().nonnegative().openapi({ type: "integer", example: 412 });

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
 * Every refusal the Durable Object can give, on every route that can reach it.
 *
 * Spread wholesale rather than picked per route, and that is honest rather
 * than lazy: the object decides, the handler cannot know which subset applies,
 * and a route that documented four of the seven would be documenting a guess.
 *
 * Deliberately not `as const`. `@hono/zod-openapi` builds a handler's allowed
 * return type from the `responses` it can read, and `readonly` properties are
 * not among them — so with `as const` every error status vanished from the
 * union and returning one was a type error against the 200 alone. The failure
 * reads as "your refusal is missing fourteen properties of Group", which is a
 * long way from "this object is frozen".
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

export type RefusalStatus = 400 | 401 | 403 | 404 | 409 | 410 | 422;

/**
 * One refusal vocabulary translated into another, in one place.
 *
 * The object speaks in codes because a code is the thing that survives being
 * read by a client. This adds the status, which is what makes the response an
 * HTTP response, and the retry kind, which is what the device acts on — see
 * `ErrorSchema`. None of the three is derived from the others.
 */
export function respond<T extends object, E extends WorkerEnv>(c: Context<E>, result: Result<T>) {
  if (result.ok) return c.json(result.value, 200);

  const { code, message } = result.error;
  return c.json(apiError(code, message, kindOf(code)), statusFor(code) as RefusalStatus);
}

/** The group's object, addressed by the id the client minted for it. */
export function group<E extends WorkerEnv>(c: Context<E>, groupId: string) {
  return c.env.GROUP.getByName(groupId);
}

/**
 * Generic over the whole Hono environment rather than pinned to one.
 *
 * `Context<E>` is invariant in `E` — it carries a `set` that writes into the
 * variables — so a helper declared against a base type cannot be handed a
 * context that has more in it. Both apps here need these two, and one of them
 * has a session while the other deliberately does not.
 */
type WorkerEnv = { Bindings: Env; Variables: Record<string, unknown> };
