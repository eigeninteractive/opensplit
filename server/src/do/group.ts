import { DurableObject } from "cloudflare:workers";

/**
 * One group's ledger, and the authorization boundary for it.
 *
 * A Durable Object processes one request at a time and owns exactly one
 * group's rows, which is what lets three separate pieces of Postgres machinery
 * collapse into ordinary code: the deferred balance-invariant trigger becomes a
 * function call with the finished shape in hand, the column guards become
 * comparisons with real before-and-after values, and `is_group_member()`
 * becomes reading its own table.
 *
 * It also makes a strictly increasing `seq` per group possible, because there
 * is exactly one writer. That is what the change feed is cursored on.
 *
 * Filled in during phase 2. Everything above this line is the reason it exists.
 */
export class Group extends DurableObject<Env> {
  /** Phase 0 liveness, so the binding and `exports` wiring can be tested. */
  async ping(): Promise<string> {
    return "group";
  }
}
