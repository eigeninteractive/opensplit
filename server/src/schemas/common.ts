import { z } from "@hono/zod-openapi";
import { createSchemaFactory } from "drizzle-zod";

import { refusalCodes } from "../do/group/refusal";

/**
 * Wire primitives shared by every schema.
 *
 * Rows are derived from their Drizzle tables with `createSelectSchema`, and
 * request bodies are `.pick()`s of those rows, so a column's type and its
 * validation are declared once. Refinements are functions so drizzle-zod still
 * applies each column's own nullability.
 */
export const { createSelectSchema } = createSchemaFactory({ zodInstance: z });

/** A client-minted identifier. */
export const IdSchema = z.string().min(1).max(64).openapi({ example: "0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f" });

/** An ISO-8601 instant, UTC, from the server's clock. */
export const TimestampSchema = z.iso.datetime().openapi({ example: "2026-09-23T11:20:41.865Z" });

/** A calendar date, `YYYY-MM-DD`. */
export const DateSchema = z.iso.date().openapi({ example: "2026-09-23" });

/** An IANA time zone the runtime knows. */
export const TimeZoneSchema = z
  .string()
  .max(64)
  .refine((name) => {
    try {
      new Intl.DateTimeFormat("en", { timeZone: name });
      return true;
    } catch {
      return false;
    }
  }, "Not a time zone.")
  .openapi({ example: "Asia/Kolkata" });

/** ISO 4217. */
export const CurrencyCodeSchema = z
  .string()
  .regex(/^[A-Z]{3}$/)
  .openapi({ example: "INR" });

/** A UPI virtual payment address. */
export const UpiVpaSchema = z
  .string()
  .regex(/^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$/)
  .openapi({ example: "ravi@okhdfcbank" });

/** A person's or a group's name. */
export const NameSchema = z.string().trim().min(1).max(100);

/** A group's sequence number: its sync cursor and the version an edit is judged against. */
export const SeqSchema = z.int().nonnegative().openapi({ example: 412 });

export const RetrySchema = z.enum(["stale", "permanent", "transient"]).openapi("Retry", {
  description: "stale: re-read, re-compose and send again. permanent: this will be refused identically forever; do not retry. transient: back off and try the same request again.",
});

export const ErrorCodeSchema = z.enum([...refusalCodes, "no_session", "not_found", "internal", "identity_already_in_use", "auth_failed"]).openapi("ErrorCode");

/** Every failure's body. The client acts on `retry`, never on the status code. */
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

/** Permanent by default: a transient failure misreported as permanent drops one write; the reverse loops. */
export function apiError(code: ErrorCode, message: string, retry: Retry = "permanent"): ApiError {
  return { error: { code, message, retry } };
}

export const errorResponse = (description: string) => ({
  description,
  content: { "application/json": { schema: ErrorSchema } },
});

export const jsonResponse = <T extends z.ZodType>(schema: T, description: string) => ({
  description,
  content: { "application/json": { schema } },
});

export const jsonBody = <T extends z.ZodType>(schema: T) => ({
  required: true,
  content: { "application/json": { schema } },
});
