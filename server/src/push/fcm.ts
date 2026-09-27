import { and, eq, inArray, isNull, ne } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { importPKCS8, SignJWT } from "jose";

import { chunked } from "../chunked";
import { deviceTokens, memberships } from "../db/d1/schema";
import type { PushData } from "../schemas/ledger";

/**
 * Wakes other members' devices after a group's write commits.
 *
 * Data-only, ids and nothing else: the device syncs and words the
 * notification with the same formatter the screens use, so a banner can never
 * disagree with the screen behind it. No queue: volume follows ledger writes,
 * and a dropped notification is acceptable.
 */

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const HTTP_TIMEOUT = 10_000;
/** One cached access token, so a burst of groups does not mint one each. */
const TOKEN_KEY = "fcm:access-token";

/** Wakes every device of the group's current members except the actor's, once per message. */
export async function wakeDevices(env: Env, groupId: string, actorProfileId: string, messages: PushData[]): Promise<void> {
  if (messages.length === 0 || !env.FCM_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT) return;

  const db = drizzle(env.DB);
  const devices = await db
    .select({ token: deviceTokens.token })
    .from(deviceTokens)
    .innerJoin(memberships, eq(memberships.profileId, deviceTokens.profileId))
    .where(and(eq(memberships.groupId, groupId), isNull(memberships.leftAt), ne(deviceTokens.profileId, actorProfileId)))
    .all();
  if (devices.length === 0) return;

  let accessToken: string;
  try {
    accessToken = await mintAccessToken(env);
  } catch (cause) {
    console.error("[push] could not mint an FCM access token", cause);
    return;
  }

  const dead = new Set<string>();
  await Promise.allSettled(messages.flatMap((data) => devices.map((device) => send(env, accessToken, device.token, data, dead))));

  for (const tokens of chunked([...dead])) await db.delete(deviceTokens).where(inArray(deviceTokens.token, tokens));
}

async function send(env: Env, accessToken: string, registration: string, data: PushData, dead: Set<string>): Promise<void> {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(HTTP_TIMEOUT),
    body: JSON.stringify({
      message: {
        token: registration,
        data,
        android: { priority: "high" },
        webpush: { headers: { Urgency: "high" } },
      },
    }),
  });
  if (response.ok) return;

  const body = await response.json().catch(() => null);
  if (isDeadToken(response.status, body)) {
    dead.add(registration);
    return;
  }
  console.error("[push] send failed", response.status, JSON.stringify(body));
}

/** Unregistered (404), or a token FCM rejects as malformed; any other 400 is our payload's fault. */
function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  if (status !== 400) return false;
  const details = (body as { error?: { details?: { "@type"?: string; errorCode?: string }[] } } | null)?.error?.details;
  return Array.isArray(details) && details.some((detail) => detail["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" && detail.errorCode === "INVALID_ARGUMENT");
}

async function mintAccessToken(env: Env): Promise<string> {
  const cached = await env.CACHE.get(TOKEN_KEY);
  if (cached) return cached;

  const account = JSON.parse(env.FCM_SERVICE_ACCOUNT) as { client_email: string; private_key: string };
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience(TOKEN_URL)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    signal: AbortSignal.timeout(HTTP_TIMEOUT),
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error(`FCM token request failed: ${response.status} ${await response.text()}`);

  const body = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
  if (typeof body.access_token !== "string") throw new Error("FCM token response carried no access_token");

  const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
  await env.CACHE.put(TOKEN_KEY, body.access_token, { expirationTtl: Math.max(60, lifetime - 300) });
  return body.access_token;
}
