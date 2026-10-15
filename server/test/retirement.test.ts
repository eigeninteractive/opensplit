import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import { unavailableApi } from "../src/api/routing";

// The production fallback, with future current versions so retirement can be
// verified before the first version has actually been retired.
function apiAt(version: number) {
  const app = new Hono<{ Bindings: Env }>();
  app.get(`/api/v${version}/health`, (c) => c.json({ ok: true }));
  app.all("/api/*", (c) => unavailableApi(c, version));
  return app;
}

describe("numbered API retirement", () => {
  it.each([
    [2, "/api/v1"],
    [2, "/api/v1/"],
    [2, "/api/v1/groups/g/entries/e"],
    [3, "/api/v1/sync"],
    [3, "/api/v2/sync"],
    [12, "/api/v10/groups/g"],
  ])("v%i retires %s for every request method", async (version, path) => {
    const app = apiAt(version);
    for (const method of ["GET", "POST", "PUT", "DELETE"]) {
      const response = await app.request(path, { method });
      expect(response.status).toBe(410);
      expect(response.headers.get("Cache-Control")).toBe("no-store");
      expect(await response.json()).toMatchObject({ error: { code: "update_required", retry: "permanent" } });
    }
  });

  it.each(["/api/sync", "/api/auth/callback/google", "/api/v0/sync", "/api/v01/sync", "/api/v-1/sync", "/api/v1x/sync", "/api/v1.0/sync", "/api/V1/sync", "/api/v2", "/api/v2/missing-operation", "/api/v3/sync", "/api/v20/sync", "/api/v999/groups/g"])("v2 returns an ordinary 404 for %s", async (path) => {
    const response = await apiAt(2).request(path);
    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({ error: { code: "not_found", retry: "permanent" } });
  });

  it("does not retire any numbered API at the v1 baseline", async () => {
    const app = apiAt(1);
    for (const path of ["/api/sync", "/api/v0/sync", "/api/v1/missing-operation", "/api/v2/sync"]) {
      expect((await app.request(path)).status).toBe(404);
    }
    const response = await app.request("/api/v1/health");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
  });
});
