import { exports as workerExports } from "cloudflare:workers";

import type { IdentityOutcome } from "../src/schemas/identity";

/** A guest account and its bearer token. */
export interface Guest {
  id: string;
  token: string;
}

export async function signInAsGuest(): Promise<Guest> {
  const response = await workerExports.default.fetch("https://opensplit.test/api/identity/guest", { method: "POST" });
  if (response.status !== 200) throw new Error(`Guest sign-in failed: ${response.status}`);

  const body = (await response.json()) as IdentityOutcome;
  if (!body.token) throw new Error("Guest sign-in returned no bearer token");
  return { id: body.account.id, token: body.token };
}
