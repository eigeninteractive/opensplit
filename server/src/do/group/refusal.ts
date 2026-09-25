/**
 * How the Durable Object says no.
 *
 * Every method returns `Result<T>` rather than throwing across the RPC
 * boundary, and the distinction it draws is the useful one: a refusal is a
 * value, a bug is an exception. "You are not a member", "this entry moved
 * since you composed the edit" and "that invite is spent" are answers the
 * object is supposed to give, and a caller that has to catch them cannot tell
 * them apart from a `TypeError` in the middle of a transaction.
 *
 * It also keeps the wire honest without relying on how workerd serializes an
 * exception. A `Result` is a plain object, so the code and the message arrive
 * intact on the other side, which is exactly what the `{error:{code,message}}`
 * envelope needs.
 *
 * And it puts the naming where the knowledge is. A client that has to map
 * database error codes to meanings is keeping a second copy of the server's
 * rules, in another language, updated by hand — and the failure mode is a
 * permanent refusal classified as retryable, which wedges an outbox. The
 * server states the kind; the client reads it.
 */
export const refusalCodes = [
  /** No session, or one the group has never heard of. */
  "not_member",
  /** No group here yet. The id is unused, not forbidden. */
  "no_group",
  /** There was one. It was archived, went a year silent while settled, and was collected. */
  "group_purged",
  /** A group already lives at this id, and somebody else made it. */
  "group_exists",
  "no_such_entry",
  "no_such_member",
  /** `sum(payers) = sum(shares) = amount` does not hold. */
  "unbalanced",
  /** Composed against a version that has since moved, in a way that moves money. */
  "stale_base",
  /** A column rule: whose name, whose payment handle, whose place. */
  "forbidden",
  /** Somebody else cannot remove a member who still owes or is owed. */
  "not_settled",
  /** The token names nothing. Deliberately the same answer as a wrong token. */
  "invite_invalid",
  "invite_spent",
  "invite_expired",
  /** This account already holds a place here, under some name. */
  "already_member",
  /** The placeholder was claimed between the peek and the join. */
  "slot_taken",
  /** Shape the edge should have caught. Present because the object checks anyway. */
  "malformed",
] as const;

export type RefusalCode = (typeof refusalCodes)[number];

export interface Refusal {
  code: RefusalCode;
  message: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: Refusal };

/**
 * Thrown inside the object, converted to a `Result` at its edge.
 *
 * Internal code throws because a refusal can happen six frames deep inside a
 * `transactionSync` and threading a result type through every helper would
 * bury the logic it is there to express. Throwing also rolls the transaction
 * back, which is what a refusal must do.
 */
export class Refused extends Error {
  override readonly name = "Refused";

  constructor(
    readonly code: RefusalCode,
    message: string,
  ) {
    super(message);
  }
}

export function refuse(code: RefusalCode, message: string): never {
  throw new Refused(code, message);
}

/**
 * Runs a method body, turning its refusals into the value the caller gets.
 *
 * Anything that is not a `Refused` is re-thrown, so a genuine bug still
 * crashes the request and shows up in the logs rather than being flattened
 * into a polite 4xx that nobody investigates.
 */
export function attempt<T>(body: () => T): Result<T> {
  try {
    return { ok: true, value: body() };
  } catch (error) {
    if (error instanceof Refused) {
      return { ok: false, error: { code: error.code, message: error.message } };
    }
    throw error;
  }
}

/**
 * What a client should do about a refusal.
 *
 * This exists because the obvious rule — "409 means a conflict a person
 * resolves, every other 4xx is permanent" — is not true of this API, and
 * believing it would wedge the outbox.
 *
 * Five codes map to 409 because 409 is genuinely the right status for all of
 * them: the request conflicts with the resource's current state. But only
 * `stale_base` is worth re-composing and retrying. `not_settled` will refuse
 * identically until somebody settles a debt; `already_member` will refuse
 * forever. A device that read the status and retried would spin.
 *
 * So the server states the kind rather than leaving the client to infer it
 * from a status code, which is the same reason `code` exists at all.
 *
 * There is no `transient` member. Transient failures are 5xx and transport
 * errors, and they never carry one of these.
 */
export type RefusalKind = "stale" | "permanent";

export function kindOf(code: RefusalCode): RefusalKind {
  return code === "stale_base" ? "stale" : "permanent";
}

/**
 * The one place a refusal becomes a status.
 *
 * Kept next to the codes so the two cannot drift. The Durable Object itself
 * never calls this — it knows nothing about HTTP — but the mapping belongs
 * with the meanings rather than in a route handler, where a new code would be
 * easy to add and easy to forget.
 *
 * `not_member` is 403 and `no_group` is 404, which does tell a caller holding
 * a group id whether that group exists. That is a deliberate departure from
 * the rule `delete_entry` follows, where "no such expense" and "not yours"
 * are deliberately the same answer — there, an entry id could name a row in
 * any group in the database, so distinguishing them answered "does this id
 * exist?" for anybody willing to ask. A group id is a client-minted UUID that
 * only its members hold, so the same question cannot be asked usefully, and
 * the two answers are worth telling apart: a device whose membership index is
 * stale needs to know whether it was removed or whether the group is gone.
 */
export function statusFor(code: RefusalCode): 400 | 403 | 404 | 409 | 410 | 422 {
  switch (code) {
    case "not_member":
    case "forbidden":
      return 403;
    case "no_group":
    case "no_such_entry":
    case "no_such_member":
    case "invite_invalid":
      return 404;
    case "group_purged":
    case "invite_expired":
      return 410;
    case "stale_base":
    case "group_exists":
    case "not_settled":
    case "invite_spent":
    case "already_member":
    case "slot_taken":
      return 409;
    case "unbalanced":
      return 422;
    case "malformed":
      return 400;
  }
}
