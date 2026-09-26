/**
 * How the group object says no: a refusal is a value (`Result`), a bug is an
 * exception. Internals `refuse()` (which also rolls back the transaction) and
 * `attempt()` turns that into the `Result` the caller receives.
 */
export const refusalCodes = [
  "not_member",
  "no_group",
  /** Archived, a year silent and settled, then collected. */
  "group_purged",
  /** A group already lives at this id, made by somebody else. */
  "group_exists",
  "no_such_entry",
  "no_such_member",
  /** `sum(payers) = sum(shares) = amount` does not hold. */
  "unbalanced",
  /** Composed against a version that has since moved money. */
  "stale_base",
  /** A column rule: whose name, whose payment handle. */
  "forbidden",
  /** Somebody else cannot remove a member who still owes or is owed. */
  "not_settled",
  "invite_invalid",
  "invite_spent",
  "invite_expired",
  "already_member",
  /** The placeholder was claimed between the peek and the join. */
  "slot_taken",
  "malformed",
] as const;

export type RefusalCode = (typeof refusalCodes)[number];

export interface Refusal {
  code: RefusalCode;
  message: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: Refusal };

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

/** Runs a body, turning refusals into values and re-throwing everything else. */
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

/** Only a stale base is worth re-composing; every other refusal repeats forever. */
export function kindOf(code: RefusalCode): "stale" | "permanent" {
  return code === "stale_base" ? "stale" : "permanent";
}

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
