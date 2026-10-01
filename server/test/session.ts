import { exports as workerExports } from "cloudflare:workers";

import type { IdentityOutcome } from "../src/schemas/identity";

/** A guest account and its bearer token. */
export interface Guest {
  id: string;
  token: string;
}

export async function signInAsGuest(): Promise<Guest> {
  // A client of its own, as each real guest is: the guest door is rate-limited per address.
  const response = await workerExports.default.fetch("https://opensplit.test/api/identity/guest", { method: "POST", headers: { "CF-Connecting-IP": randomIp() } });
  if (response.status !== 200) throw new Error(`Guest sign-in failed: ${response.status}`);

  const body = (await response.json()) as IdentityOutcome;
  if (!body.token) throw new Error("Guest sign-in returned no bearer token");
  return { id: body.account.id, token: body.token };
}

/** A distinct client address, so one test's guests do not spend another's rate limit. */
export function randomIp(): string {
  return Array.from({ length: 4 }, () => Math.floor(Math.random() * 256)).join(".");
}
