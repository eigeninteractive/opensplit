import { app } from "./app";
import { refreshRates, weeklySweep } from "./scheduled";

export { Fx } from "./do/fx/index";
export { Group } from "./do/group";

/**
 * The Worker entrypoint, kept apart from `app.ts` because the Durable Object
 * classes import `cloudflare:workers`, which `scripts/write-openapi.ts` cannot
 * load under Node.
 */
export default {
  fetch: app.fetch,

  // `waitUntil`, or the runtime cancels the work when the handler returns.
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
