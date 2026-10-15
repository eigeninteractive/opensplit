import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { APIError } from "better-auth/api";
import type { ContentfulStatusCode } from "hono/utils/http-status";

import { accountRoutes } from "./api/account";
import { inviteRoutes } from "./api/invites";
import { ledgerRoutes } from "./api/ledger";
import { referenceRoutes } from "./api/reference";
import { unavailableApi } from "./api/routing";
import { type AppEnv, services } from "./context";
import { identityRoutes } from "./identity/routes";
import { openApiDocument } from "./openapi";
import { apiBasePath, authBasePath } from "./paths";
import { apiError, jsonResponse } from "./schemas/common";
import { AccountSchema } from "./schemas/identity";
import { EntrySnapshotSchema, GroupEventPayloadSchema, GroupLinkSchema, GroupSchema, LinkEventPayloadSchema, MemberEventPayloadSchema, PushDataSchema } from "./schemas/ledger";

const healthRoute = createRoute({
  method: "get",
  operationId: "health",
  path: "/health",
  tags: ["meta"],
  summary: "Whether the Worker is answering",
  responses: {
    200: jsonResponse(z.object({ ok: z.literal(true), service: z.literal("opensplit"), now: z.iso.datetime() }).openapi("Health"), "It is"),
  },
});

/** A validation failure is an ordinary refusal, in the same envelope. Child apps inherit this hook. */
const app = new OpenAPIHono<AppEnv>({
  defaultHook: (result, c) => {
    if (!result.success) return c.json(apiError("malformed", result.error.issues[0]?.message ?? "Invalid."), 400);
  },
});

// Emit this router's relative paths with the shared OpenAPI server URL. The
// parent router owns the mount and the operational endpoints, not the contract.
const api = new OpenAPIHono<AppEnv>();

/**
 * Components that some field holds as nullable, registered before any route
 * uses them. The generator builds a component from its first use, so one first
 * met through `.nullable()` would itself be emitted nullable, everywhere.
 */
for (const schema of [GroupSchema, GroupLinkSchema, AccountSchema, EntrySnapshotSchema, MemberEventPayloadSchema, GroupEventPayloadSchema, LinkEventPayloadSchema]) {
  api.openAPIRegistry.register(schema.meta()?.id as string, schema);
}

// Only the current contract reaches account and ledger services.
app.use(`${apiBasePath}/*`, services);

// Better Auth's own handler, only for the redirect Google sends the browser back to.
app.on(["GET", "POST"], [`${authBasePath}/callback/*`, `${authBasePath}/error`], (c) => c.var.auth.handler(c.req.raw));

const health = () => ({ ok: true as const, service: "opensplit" as const, now: new Date().toISOString() });
api.openapi(healthRoute, (c) => c.json(health(), 200));
// Deployment probes remain stable across app contract versions.
app.get("/api/health", (c) => c.json(health(), 200));
identityRoutes(api);
ledgerRoutes(api);
inviteRoutes(api);
accountRoutes(api);
referenceRoutes(api);

api.openAPIRegistry.registerComponent("securitySchemes", "bearer", { type: "http", scheme: "bearer", description: "The session token from `set-auth-token`, on Android." });
api.openAPIRegistry.registerComponent("securitySchemes", "cookie", { type: "apiKey", in: "cookie", name: "better-auth.session_token", description: "The HttpOnly session cookie, on the web." });
// Sent over FCM rather than HTTP, so no route references it.
api.openAPIRegistry.register("PushData", PushDataSchema);
app.route(apiBasePath, api);
app.get("/api/openapi.json", (c) => c.json(api.getOpenAPIDocument(openApiDocument)));

app.all("/api/*", (c) => unavailableApi(c));

/**
 * No asset matched. A path under `/app` is a client deep link such as
 * `/app/join/:token`, answered with the client's own document (none of the
 * platform's `not_found_handling` modes picks that document); anything else is
 * the 404 page.
 */
app.all("*", async (c) => {
  const url = new URL(c.req.url);
  if (url.pathname === "/app" || url.pathname.startsWith("/app/")) {
    const response = await c.env.ASSETS.fetch(new Request(new URL("/app/index.html", url.origin), { headers: c.req.raw.headers }));
    return new Response(response.body, { status: response.status === 404 ? 404 : 200, headers: response.headers });
  }

  const notFound = await c.env.ASSETS.fetch(new Request(new URL("/404.html", url.origin)));
  if (notFound.status === 200) return new Response(notFound.body, { status: 404, headers: notFound.headers });
  return c.text("Not found", 404);
});

app.onError((error, c) => {
  // Better Auth refusing something (a wrong or expired code, say) is a refusal, not a crash.
  if (error instanceof APIError && error.statusCode < 500) {
    return c.json(apiError("auth_failed", error.body?.message ?? error.message), error.statusCode as ContentfulStatusCode);
  }
  console.error("unhandled", error);
  // Transient: a crash says nothing about whether the same request would succeed, and a write
  // told "permanent" is set aside on the device until somebody retries it by hand.
  return c.json(apiError("internal", "Something went wrong.", "transient"), 500);
});

export { api, app };
