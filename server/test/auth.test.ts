import { env, exports as workerExports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

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

  /**
   * The guard on the invite-claim path.
   *
   * Claiming a placeholder adopts the name a friend typed, but only when the
   * profile has no name of its own. The anonymous plugin invents a display
   * name; storing it would make that check always false, and somebody arriving
   * on a link would show up to their friends as whatever the plugin made up
   * instead of as the person they were invited as.
   */
  it("does not store the name the anonymous plugin invents", async () => {
    const guest = await signInAsGuest();

    const profile = await profileOf(guest.id);
    expect(profile?.display_name).toBeNull();
  });

  it("resolves the session from a bearer token", async () => {
    const guest = await signInAsGuest();

    const response = await workerExports.default.fetch("https://opensplit.test/api/auth/get-session", { headers: { Authorization: `Bearer ${guest.token}` } });

    expect(response.status).toBe(200);
    const body = (await response.json()) as { user?: { id: string } } | null;
    expect(body?.user?.id).toBe(guest.id);
  });

  it("gives two guests two accounts", async () => {
    const first = await signInAsGuest();
    const second = await signInAsGuest();

    expect(first.id).not.toBe(second.id);
  });
});
