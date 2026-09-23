import { exports as workerExports } from "cloudflare:workers";

/**
 * A guest account and its bearer token.
 *
 * The token is read off `set-auth-token` and checked rather than asserted with
 * `!`, because a missing header here does not mean a broken test — it means the
 * bearer plugin has stopped handing Android a session, which is a real defect
 * worth a sentence rather than a `TypeError` three lines later.
 */
export interface Guest {
  id: string;
  token: string;
}

export async function signInAsGuest(): Promise<Guest> {
  const response = await workerExports.default.fetch("https://opensplit.test/api/auth/sign-in/anonymous", { method: "POST", headers: { "Content-Type": "application/json" } });

  if (response.status !== 200) {
    throw new Error(`Guest sign-in failed: ${response.status}`);
  }

  const body = (await response.json()) as { user: { id: string } };
  const token = response.headers.get("set-auth-token");
  if (!token) {
    throw new Error("Guest sign-in returned no set-auth-token header");
  }

  return { id: body.user.id, token };
}
