import { z } from "@hono/zod-openapi";

/**
 * The wire format, declared once.
 *
 * Each schema here is three things at once: the runtime validator that rejects
 * a malformed request, the TypeScript type the handler is written against, and
 * the OpenAPI definition the Dart client is generated from. There is no second
 * place the wire format is described, so there is nowhere for it to drift —
 * which is the whole reason for the dependency.
 */

/**
 * Every failure crosses the wire in this shape.
 *
 * It replaces reading Postgres SQLSTATEs on the device and inferring from them
 * whether a retry is worth attempting — a lookup table that had to know that
 * `23514` was the balance invariant, that `42501` was a policy refusal, and
 * that `PT409` had to be raised in place of `40001` because PostgREST would
 * otherwise retry a permanent refusal until the gateway timed out.
 *
 * Now the server states the kind and the client maps the status:
 *
 *   409  a conflict a person has to resolve — retrying sends the same stale
 *        base forever, but it is not permanent either
 *   4xx  refused identically forever; retrying only wedges the outbox
 *   5xx  worth backing off and trying again
 */
export const ErrorSchema = z
  .object({
    error: z.object({
      code: z.string().openapi({ example: "stale_base" }),
      message: z.string(),
    }),
  })
  .openapi("Error");

export type ApiError = z.infer<typeof ErrorSchema>;

export function apiError(code: string, message: string): ApiError {
  return { error: { code, message } };
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
