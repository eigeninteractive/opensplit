import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

/**
 * Phase 0's exit criterion, as a test: the Worker answers, the bindings
 * resolve, and the routing model behaves the way the configuration claims.
 *
 * The last of those is the one worth having. "Assets are served first and a
 * miss falls through to the Worker" is a sentence in the docs; this is the
 * thing that says it is true of this configuration.
 */
describe("the Worker is wired up", () => {
  it("answers a health check", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/api/health");

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      ok: true,
      service: "opensplit",
    });
  });

  it("answers an unknown API path with the error envelope, not HTML", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/api/nope");

    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({
      error: { code: "not_found" },
    });
  });

  /**
   * The sync routes are mounted at `/api`, which is also where the public ones
   * live. A wildcard `use()` in that sub-app would claim `/api/nope` and answer
   * 401 — telling an unauthenticated caller nothing useful and contradicting
   * the health check sitting beside it.
   */
  it("does not let the authenticated routes claim paths they do not own", async () => {
    for (const path of ["/api/nope", "/api/groups-ish", "/api/bootstrapped"]) {
      const response = await workerExports.default.fetch(`https://opensplit.test${path}`);
      expect(response.status, path).toBe(404);
    }

    const health = await workerExports.default.fetch("https://opensplit.test/api/health");
    expect(health.status).toBe(200);
  });

  it("serves a single-page-application deep link from the app document", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/app/join/some-token");

    // 200 rather than 404: go_router reads the path and decides, and it can
    // only do that if the document arrives.
    expect(response.status).toBe(200);
    expect(await response.text()).toContain("opensplit-app-shell");
  });

  it("does not answer a missing site page with the app document", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/nonsense");

    expect(response.status).toBe(404);
  });
});

describe("the Durable Object bindings resolve", () => {
  it("reaches a group object by name", async () => {
    const stub = env.GROUP.getByName("group-under-test");

    expect(await stub.ping()).toBe("group");
  });

  it("reaches the singleton rate writer", async () => {
    const stub = env.FX.getByName("global");

    expect(await stub.ping()).toBe("fx");
  });
});
