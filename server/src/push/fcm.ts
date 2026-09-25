import { inArray } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { importPKCS8, SignJWT } from "jose";

import { deviceTokens } from "../db/d1/schema";

/**
 * Waking the other members' devices.
 *
 * Called by a group's Durable Object after its own write has committed,
 * inside `ctx.waitUntil`. In-process rather than over HTTP, which is what
 * removes the shared secret: a function reached over the network has to prove
 * who is calling it, and a function the object calls directly does not.
 *
 * ## The message carries ids and nothing else
 *
 * No amount, no name, no description. Two reasons, and the second is the one
 * that matters. The device has to pull the delta anyway to stay consistent, so
 * anything included here would be a second source of truth for the same fact.
 * And formatting the text on the server would mean reimplementing currency
 * exponents, rounding and each recipient's share outside Dart, where it would
 * drift from the app silently — a banner saying one number and the screen
 * behind it saying another.
 *
 * So it is a data-only message. The device syncs, then says what happened using
 * the same formatter the screens use.
 *
 * ## No queue
 *
 * Notification volume is proportional to ledger writes, not to app opens, so it
 * was never the cost driver; and an awaited `fetch` yields the event loop, so a
 * pending send does not stall the next expense write. If reliability ever needs
 * to be tighter, `waitUntil(wakeDevices(…))` becomes `env.QUEUE.send(…)` behind
 * the same call site and nothing upstream changes.
 */

/** One thing that happened, and who should hear about it. */
export interface Notice {
  groupId: string;
  eventId: string;

  /**
   * Which kinds wake a device: an expense, somebody arriving, somebody leaving.
   *
   * Not renames, archives or links. Those belong in the activity feed, which is
   * read on purpose, rather than on a lock screen — and a notification nobody
   * wanted is how notifications stop being read at all.
   */
  kind: "entry" | "member_joined" | "member_left";

  /** What the event is about: an entry id, or a member id. */
  subjectId: string | null;

  /**
   * Accounts to wake.
   *
   * The **actor** is already excluded, not the author. On an edit those are
   * usually different people, and the author is precisely who needs to hear
   * that somebody changed their expense.
   */
  profileIds: string[];
}

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const HTTP_TIMEOUT = 10_000;

/**
 * Where the minted OAuth token is shared.
 *
 * KV rather than a module variable, and that is the one real change from the
 * Edge Function this replaces. There is one isolate there and potentially
 * hundreds of group objects here, each in its own isolate in its own location:
 * a per-instance cache would mint a token per active group per hour, which is
 * hundreds of round trips to Google to say the same thing.
 */
const TOKEN_KEY = "fcm:access-token";

export async function wakeDevices(env: Env, notices: Notice[]): Promise<void> {
  if (notices.length === 0) return;

  // Unconfigured is an ordinary state, not a failure: a fork, a local
  // `wrangler dev`, a deployment that has not set Firebase up. Push is the one
  // feature this app is fully usable without.
  if (!env.FCM_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT) return;

  const db = drizzle(env.DB);
  const stale = new Set<string>();

  for (const notice of notices) {
    if (notice.profileIds.length === 0) continue;

    const targets = await db.select({ token: deviceTokens.token }).from(deviceTokens).where(inArray(deviceTokens.profileId, notice.profileIds)).all();
    if (targets.length === 0) continue;

    let token: string;
    try {
      token = await accessToken(env);
    } catch (cause) {
      // Loudly, and once, rather than sending every notice unauthenticated.
      console.error("[push] could not mint an FCM access token", cause);
      return;
    }

    // allSettled, not all: one recipient's network failure must not abandon the
    // rest of the group half-notified.
    await Promise.allSettled(targets.map(async ({ token: registration }) => send(env, token, registration, notice, stale)));
  }

  if (stale.size > 0) {
    await db.delete(deviceTokens).where(inArray(deviceTokens.token, [...stale]));
  }
}

async function send(env: Env, accessToken: string, registration: string, notice: Notice, stale: Set<string>): Promise<void> {
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(HTTP_TIMEOUT),
    body: JSON.stringify({
      message: {
        token: registration,
        /**
         * Data-only. A `notification` block would make the operating system
         * draw its own banner from server-formatted text, which is the whole
         * thing this design exists to avoid.
         *
         * Snake-case keys because the Dart background handler reads them that
         * way, and because FCM requires every data value to be a string.
         */
        data: {
          kind: notice.kind,
          event_id: notice.eventId,
          subject_id: notice.subjectId ?? "",
          group_id: notice.groupId,
        },
        android: { priority: "high" },
        webpush: { headers: { Urgency: "high" } },
      },
    }),
  });

  if (response.ok) return;

  const body = await response.json().catch(() => null);
  if (isDeadToken(response.status, body)) {
    stale.add(registration);
    return;
  }
  console.error("[push] send failed", response.status, JSON.stringify(body));
}

/**
 * Whether a send failure means this registration is dead for good.
 *
 * `UNREGISTERED` (404) always does. `INVALID_ARGUMENT` (400) is the trap: FCM
 * returns it both for a token it cannot parse **and** for a malformed message,
 * and the two are told apart only by the `details` array. A fan-out sends an
 * identical payload to everyone, so treating every 400 as a dead token means
 * one payload bug deletes every device in the group and each of those people
 * has to reinstall to recover.
 */
function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  if (status !== 400) return false;

  const details = (body as { error?: { details?: unknown[] } })?.error?.details;
  if (!Array.isArray(details)) return false;

  // A payload problem is reported as google.rpc.BadRequest with fieldViolations.
  // Only the FcmError detail describes the registration itself.
  return details.some((detail) => (detail as { "@type"?: string })?.["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" && (detail as { errorCode?: string })?.errorCode === "INVALID_ARGUMENT");
}

/**
 * An OAuth token for the FCM v1 API, minted from the service account.
 *
 * `jose` handles the PKCS#8 parsing and base64url encoding. Doing it by hand
 * meant stripping PEM armour with regexes and running JSON through `btoa`,
 * which throws on any non-ASCII character and produces standard base64 where
 * the JWT spec requires base64url.
 */
async function accessToken(env: Env): Promise<string> {
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

  if (!response.ok) {
    throw new Error(`FCM token request failed: ${response.status} ${await response.text()}`);
  }

  const body = (await response.json()) as { access_token?: unknown; expires_in?: unknown };
  if (typeof body.access_token !== "string") {
    throw new Error("FCM token response carried no access_token");
  }

  /**
   * Cached for slightly less than its life.
   *
   * KV's own TTL does the expiry, with five minutes of slack so a token cannot
   * go stale between the read above and the send below — and a minimum of sixty
   * seconds, which is the floor KV enforces.
   */
  const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
  await env.CACHE.put(TOKEN_KEY, body.access_token, { expirationTtl: Math.max(60, lifetime - 300) });

  return body.access_token;
}
