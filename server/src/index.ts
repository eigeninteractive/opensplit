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
   * Three schedules, dispatched on the cron expression that fired. Filled in
   * across phases 5 and 7; see the plan.
   */
  async scheduled(controller, _env, _ctx): Promise<void> {
    switch (controller.cron) {
      case "0 4 * * *":
        // Exchange rates.
        break;
      case "30 4 * * *":
        // Archive and purge dormant groups.
        break;
      case "0 5 * * 0":
        // Abandoned guest accounts, membership index reconciliation.
        break;
    }
  },
} satisfies ExportedHandler<Env>;
