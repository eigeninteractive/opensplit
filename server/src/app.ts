import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { ledgerRoutes } from "./api/ledger";
import { type AppEnv, services } from "./context";
import { identityRoutes } from "./identity/routes";
import { openApiDocument } from "./openapi";
import { apiError, jsonResponse } from "./schemas/common";

/**
 * Liveness, and the one route that is not about the ledger.
 *
 * Declared with `createRoute` like everything else rather than as a plain Hono
 * handler, so it appears in the committed contract. An endpoint missing from
 * the spec is an endpoint the generated client cannot call and nobody reviewing
 * the diff can see.
 */
const healthRoute = createRoute({
  method: "get",
  operationId: "health",
  path: "/api/health",
  tags: ["meta"],
  summary: "Whether the Worker is answering",
  responses: {
    200: jsonResponse(z.object({ ok: z.literal(true), service: z.literal("opensplit"), now: z.iso.datetime() }).openapi("Health"), "It is"),
  },
});

/**
 * A validation failure is an ordinary refusal and has to look like one.
 *
 * Without this hook `@hono/zod-openapi` answers with its own body shape, so a
 * malformed request would be the single endpoint in the API whose error the
 * client could not parse — and the client decides whether to retry by reading
 * that body.
 */
const app = new OpenAPIHono<AppEnv>({
  defaultHook: (result, c) => {
    if (result.success) return;
    return c.json(apiError("bad_request", result.error.issues[0]?.message ?? "Invalid."), 400);
  },
});

// The database and the auth instance, on every request. See context.ts.
app.use("*", services);

app.openapi(healthRoute, (c) => c.json({ ok: true, service: "opensplit", now: new Date().toISOString() }, 200));

/**
 * Better Auth's own endpoints: the OAuth dance, code verification, session
 * lookup, sign-out.
 *
 * The three flows that decide whether somebody's ledger survives attaching an
 * identity are deliberately **not** here — they live under `/api/identity/*`,
 * which wraps Better Auth's server API. See `identity/routes.ts` for why.
 */
app.on(["GET", "POST"], "/api/auth/*", (c) => c.var.auth.handler(c.req.raw));

app.route("/api/identity", identityRoutes());

// The sync surface. Everything about a group goes through its own object.
app.route("/api", ledgerRoutes());

/**
 * The contract, served and committed.
 *
 * Emitted as OpenAPI **3.0.3** rather than 3.1: nothing here needs 3.1, and
 * support for it across Dart generators is uneven. `docs/openapi.json` is
 * generated from this same document and checked for drift in CI, so a change to
 * the wire format cannot land without showing up in review.
 */
app.doc("/api/openapi.json", openApiDocument);

app.all("/api/*", (c) => c.json(apiError("not_found", "No such endpoint."), 404));

/**
 * No asset matched, and it is not an API call.
 *
 * Static assets are served ahead of this Worker, so reaching here means either
 * a single-page-application deep link — `/app/join/:token`, `/app/g/:id` — or a
 * genuinely missing page. The first is answered with the app's own document so
 * go_router can take it from there; the second is a 404.
 *
 * This is why `assets.not_found_handling` is left alone: its automatic
 * single-page-application mode would answer `/app/join/xyz` with the marketing
 * site's `index.html`, which is a different document at a different path.
 */
app.all("*", async (c) => {
  const url = new URL(c.req.url);
  if (url.pathname === "/app" || url.pathname.startsWith("/app/")) {
    const document = new URL("/app/index.html", url.origin);
    const response = await c.env.ASSETS.fetch(new Request(document, { headers: c.req.raw.headers }));
    return new Response(response.body, {
      status: response.status === 404 ? 404 : 200,
      headers: response.headers,
    });
  }

  const notFound = await c.env.ASSETS.fetch(new Request(new URL("/404.html", url.origin)));
  if (notFound.status === 200) {
    return new Response(notFound.body, {
      status: 404,
      headers: notFound.headers,
    });
  }
  return c.text("Not found", 404);
});

app.onError((error, c) => {
  console.error("unhandled", error);
  return c.json(apiError("internal", "Something went wrong."), 500);
});

export { app };
