import { exports as workerExports } from "cloudflare:workers";

import type { IdentityOutcome } from "../src/schemas/identity";
import type { ChangePage, GroupCursor, Pull } from "../src/schemas/ledger";

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

const ORIGIN = "https://opensplit.test";

/** The sync route, as the app calls it. */
export function pullResponse(guest: Guest | null, groups: GroupCursor[], limit = 200): Promise<Response> {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (guest) headers.set("Authorization", `Bearer ${guest.token}`);
  return workerExports.default.fetch(`${ORIGIN}/api/sync`, { method: "POST", headers, body: JSON.stringify({ groups, limit }) });
}

export async function pull(guest: Guest, groups: GroupCursor[], limit = 200): Promise<Pull> {
  const response = await pullResponse(guest, groups, limit);
  if (response.status !== 200) throw new Error(`Pull failed with ${response.status}: ${await response.text()}`);
  return (await response.json()) as Pull;
}

/** One group's page past `since`, failing the test with the refusal's own words if it is refused. */
export async function changes(guest: Guest, groupId: string, since = 0, limit = 200): Promise<ChangePage> {
  const { pages, refusals } = await pull(guest, [{ groupId, since }], limit);
  const [refused] = refusals;
  if (refused) throw new Error(`Refused with ${refused.code}: ${refused.message}`);
  const [page] = pages;
  if (!page) throw new Error("The pull answered no page.");
  return page;
}
