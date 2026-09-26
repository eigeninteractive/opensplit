import { inArray } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { importPKCS8, SignJWT } from "jose";

import { deviceTokens } from "../db/d1/schema";
import type { Notice } from "../do/group/notices";

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

export async function wakeDevices(env: Env, notices: Notice[]): Promise<void> {
  if (notices.length === 0 || !env.FCM_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT) return;

  const db = drizzle(env.DB);
  const profileIds = [...new Set(notices.flatMap((notice) => notice.profileIds))];
  const devices = await db.select({ token: deviceTokens.token, profileId: deviceTokens.profileId }).from(deviceTokens).where(inArray(deviceTokens.profileId, profileIds)).all();
  if (devices.length === 0) return;

  let accessToken: string;
  try {
    accessToken = await mintAccessToken(env);
  } catch (cause) {
    console.error("[push] could not mint an FCM access token", cause);
    return;
  }

  const dead = new Set<string>();
  const sends = notices.flatMap((notice) => devices.filter((device) => notice.profileIds.includes(device.profileId)).map((device) => send(env, accessToken, device.token, notice, dead)));
  await Promise.allSettled(sends);

  if (dead.size > 0) await db.delete(deviceTokens).where(inArray(deviceTokens.token, [...dead]));
}

async function send(env: Env, accessToken: string, registration: string, notice: Notice, dead: Set<string>): Promise<void> {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(HTTP_TIMEOUT),
    body: JSON.stringify({
      message: {
        token: registration,
        data: notice.data,
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
