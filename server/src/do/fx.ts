import { DurableObject } from "cloudflare:workers";

/**
 * The only writer of exchange rates.
 *
 * A singleton, reached with `getByName("global")`. It holds the rate history in
 * its own SQLite and publishes one blob per month to KV, where clients read it.
 *
 * Singleton rather than writing KV from both the daily cron and an on-demand
 * backfill, because KV is last-write-wins: two writers rebuilding the same
 * month's blob would silently drop whichever rate landed first. One writer is
 * the cheap fix, and serializing writers is what this primitive is for.
 *
 * Filled in during phase 5.
 */
export class Fx extends DurableObject<Env> {
  /** Phase 0 liveness, so the binding and `exports` wiring can be tested. */
  async ping(): Promise<string> {
    return "fx";
  }
}
