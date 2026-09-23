import { app } from "./app";

export { Fx } from "./do/fx";
export { Group } from "./do/group";

/**
 * The Worker entrypoint.
 *
 * Deliberately thin, and separate from `app.ts`, because the Durable Object
 * classes re-exported here import `cloudflare:workers` — a module that exists
 * only inside the runtime. Keeping the Hono app in its own file is what lets
 * `scripts/write-openapi.ts` import it under plain Node to write the committed
 * contract.
 */
export default {
  fetch: app.fetch,

  /**
   * Two schedules, dispatched on the cron expression that fired. Filled in
   * across phases 5 and 7; see the plan.
   *
   * Archiving and collecting dormant groups used to be the third, and is not
   * here: every group sets its own alarm, so there is nothing central left to
   * sweep. See `src/do/group/upkeep.ts`.
   */
  async scheduled(controller, _env, _ctx): Promise<void> {
    switch (controller.cron) {
      case "0 4 * * *":
        // Exchange rates.
        break;
      case "0 5 * * 0":
        // Abandoned guest accounts, membership index reconciliation.
        break;
    }
  },
} satisfies ExportedHandler<Env>;
