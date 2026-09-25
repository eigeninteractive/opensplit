import { z } from "@hono/zod-openapi";
import { createSchemaFactory } from "drizzle-zod";

import { refusalCodes } from "../do/group/refusal";

/**
 * The wire format, declared once.
 *
 * Each schema here is the runtime validator, the TypeScript type the handler
 * is written against, and the OpenAPI definition the Dart client is generated
 * from. A row the server returns is derived from its Drizzle table with
 * [createSelectSchema], so a column is declared in exactly one place.
 */

/** drizzle-zod, building on the Zod that `@hono/zod-openapi` extends with `.openapi()`. */
export const { createSelectSchema } = createSchemaFactory({ zodInstance: z });

/**
 * Every failure crosses the wire in this shape.
 *
 * A code the server chose, rather than a status the client interprets. The
 * alternative is a lookup table on the device that maps the storage layer's
 * error numbers to meanings — a second copy of the server's rules, in another
 * language, maintained by hand.
 *
 * The server states both the kind and what to do about it, and `retry` is the
 * second half of that. Leaving it to the client meant inferring intent from a
 * status code, which does not survive contact with this API: six refusals are
 * a truthful 409 — the request really does conflict with the resource's
 * current state — and only `stale_base` is worth composing again.
 * `not_settled` refuses identically until somebody settles a debt;
 * `already_member` refuses forever. A device reading the number would spin on
 * its outbox.
 */
export const RetrySchema = z.enum(["stale", "permanent", "transient"]).openapi("Retry", {
  description: "stale: re-read, re-compose and send again. permanent: this will be refused identically forever; do not retry. transient: back off and try the same request again.",
});

/**
 * Every code the Worker can answer with: the group object's refusals, plus the
 * few the Worker itself gives before an object is involved.
 */
export const ErrorCodeSchema = z.enum([...refusalCodes, "no_session", "not_found", "internal", "identity_already_in_use"]).openapi("ErrorCode");

export const ErrorSchema = z
  .object({
    error: z.object({
      code: ErrorCodeSchema,
      message: z.string(),
      retry: RetrySchema,
    }),
  })
  .openapi("Error");

export type ApiError = z.infer<typeof ErrorSchema>;
export type Retry = z.infer<typeof RetrySchema>;
export type ErrorCode = z.infer<typeof ErrorCodeSchema>;

/**
 * Permanent by default, because that is the safe way to be wrong.
 *
 * A permanent refusal reported as transient loops. A transient failure
 * reported as permanent drops one write and says so. The first is worse, so
 * anything that has not thought about it gets the second.
 */
export function apiError(code: ErrorCode, message: string, retry: Retry = "permanent"): ApiError {
  return { error: { code, message, retry } };
}

/** A response body that is only ever an error, for the standard refusals. */
export const errorResponse = (description: string) => ({
  description,
  content: { "application/json": { schema: ErrorSchema } },
});

export const jsonResponse = <T extends z.ZodTypeAny>(schema: T, description: string) => ({
  description,
  content: { "application/json": { schema } },
});

/**
 * An identifier the client invented.
 *
 * Group, member and entry ids are all minted on the device — that is what lets
 * the app record an expense with no connection and push it later — so the
 * server validates their shape and never issues them.
 */
export const IdSchema = z.string().min(1).max(64).openapi({
  example: "0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f",
});

/** An ISO-8601 instant, always UTC, always from the server's clock. */
export const TimestampSchema = z.iso.datetime().openapi({
  example: "2026-09-23T11:20:41.865Z",
});
