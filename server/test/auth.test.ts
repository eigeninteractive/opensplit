import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

import type { Session } from "../src/schemas/identity";
import { signInAsGuest } from "./session";

interface ProfileRow {
  id: string;
  display_name: string | null;
  upi_vpa: string | null;
}

async function profileOf(id: string): Promise<ProfileRow | null> {
  return env.DB.prepare("select id, display_name, upi_vpa from profiles where id = ?1").bind(id).first<ProfileRow>();
}

describe("guest accounts", () => {
  it("creates a real account with no credentials", async () => {
    const guest = await signInAsGuest();

    const user = await env.DB.prepare("select id, is_anonymous as isAnonymous from user where id = ?1").bind(guest.id).first<{ id: string; isAnonymous: number }>();

    expect(user?.isAnonymous).toBeTruthy();
  });

  it("gives every new account a profile row", async () => {
    const guest = await signInAsGuest();

    expect(await profileOf(guest.id)).not.toBeNull();
  });

  /** The guard on the invite-claim path. */
  it("does not store the name the anonymous plugin invents", async () => {
    const guest = await signInAsGuest();

    const profile = await profileOf(guest.id);
    expect(profile?.display_name).toBeNull();
  });

  it("resolves the session from a bearer token", async () => {
    const guest = await signInAsGuest();

    const response = await workerExports.default.fetch("https://opensplit.test/api/identity/session", { headers: { Authorization: `Bearer ${guest.token}` } });

    expect(response.status).toBe(200);
    const body = (await response.json()) as Session;
    expect(body.account).toEqual({ id: guest.id, isAnonymous: true, email: null, displayName: null });
  });

  it("gives two guests two accounts", async () => {
    const first = await signInAsGuest();
    const second = await signInAsGuest();

    expect(first.id).not.toBe(second.id);
  });
});
