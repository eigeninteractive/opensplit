import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { APIError } from "better-auth/api";
import type { ContentfulStatusCode } from "hono/utils/http-status";

import { accountRoutes } from "./api/account";
import { inviteRoutes } from "./api/invites";
import { ledgerRoutes } from "./api/ledger";
import { referenceRoutes } from "./api/reference";
import { type AppEnv, services } from "./context";
import { identityRoutes } from "./identity/routes";
import { openApiDocument } from "./openapi";
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

/**
 * Components that some field holds as nullable, registered before any route
 * uses them. The generator builds a component from its first use, so one first
 * met through `.nullable()` would itself be emitted nullable, everywhere.
 */
for (const schema of [GroupSchema, GroupLinkSchema, AccountSchema, EntrySnapshotSchema, MemberEventPayloadSchema, GroupEventPayloadSchema, LinkEventPayloadSchema]) {
  app.openAPIRegistry.register(schema.meta()?.id as string, schema);
}

app.use("/api/*", services);

// Better Auth's own handler, only for the redirect Google sends the browser back to.
app.on(["GET", "POST"], ["/api/auth/callback/*", "/api/auth/error"], (c) => c.var.auth.handler(c.req.raw));

const api = new OpenAPIHono<AppEnv>();
api.openapi(healthRoute, (c) => c.json({ ok: true as const, service: "opensplit" as const, now: new Date().toISOString() }, 200));
identityRoutes(api);
ledgerRoutes(api);
inviteRoutes(api);
accountRoutes(api);
referenceRoutes(api);
app.route("/api", api);

app.openAPIRegistry.registerComponent("securitySchemes", "bearer", { type: "http", scheme: "bearer", description: "The session token from `set-auth-token`, on Android." });
app.openAPIRegistry.registerComponent("securitySchemes", "cookie", { type: "apiKey", in: "cookie", name: "better-auth.session_token", description: "The HttpOnly session cookie, on the web." });
// Sent over FCM rather than HTTP, so no route references it.
app.openAPIRegistry.register("PushData", PushDataSchema);
app.doc("/api/openapi.json", openApiDocument);

app.all("/api/*", (c) => c.json(apiError("not_found", "No such endpoint."), 404));

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
  return c.json(apiError("internal", "Something went wrong."), 500);
});

export { app };
