import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

/** Phase 0's exit criterion, as a test: the Worker answers, the bindings resolve, and the routing model behaves the way the configuration claims. */
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

  /** These three run against `test/fixtures/assets`, not the real bundle — see vitest.config.ts. */
  it("serves a deep link from the client's own document", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/app/join/some-token");

    // 200 rather than 404: go_router reads the path and decides, and it can
    // only do that if the document arrives.
    expect(response.status).toBe(200);
    expect(await response.text()).toContain("Client shell");
  });

  it("answers a missing site page with the 404 page, and a 404", async () => {
    const response = await workerExports.default.fetch("https://opensplit.test/nonsense");
    const body = await response.text();

    expect(response.status).toBe(404);
    // The status and the document have to disagree with each other in exactly
    // this way: a real 404 for a crawler, a readable page for a person.
    expect(body).toContain("Not found");
    expect(body).not.toContain("Client shell");
  });

  it("does not answer a missing site page with the landing page", async () => {
    // What `not_found_handling: "single-page-application"` would do, and it
    // would do it to /app/join/xyz as well.
    const response = await workerExports.default.fetch("https://opensplit.test/nonsense");

    expect(await response.text()).not.toContain("Site root");
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
