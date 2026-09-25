import { app } from "./app";
import { refreshRates, weeklySweep } from "./scheduled";

export { Fx } from "./do/fx/index";
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
   * Two schedules, dispatched on the cron expression that fired. Dormant
   * groups are not swept here: each sets its own alarm (`do/group/upkeep.ts`).
   *
   * `waitUntil` rather than an awaited call, so the runtime keeps the
   * invocation alive for the whole sweep — a scheduled handler that returns
   * before its work finishes has that work cancelled, silently, and the only
   * symptom is rates that stop arriving.
   */
  async scheduled(controller, env, ctx): Promise<void> {
    switch (controller.cron) {
      case "0 4 * * *":
        ctx.waitUntil(refreshRates(env));
        break;
      case "0 5 * * 0":
        ctx.waitUntil(weeklySweep(env));
        break;
    }
  },
} satisfies ExportedHandler<Env>;
