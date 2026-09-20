// Fan-out for recorded group events: wake the other members' devices.
//
// Triggered by a trigger on `group_events`. It sends a data-only FCM message
// carrying nothing but ids and which kind of event this was — no amounts, no
// names, no description.
//
// Two reasons for that. First, the client has to pull the delta anyway to stay
// consistent, so anything included here would be a second source of truth.
// Second, formatting the text server-side would mean reimplementing currency
// exponents, rounding and each recipient's share outside Dart, where it would
// drift from the app silently. The device already knows how to say it.
//
// Deploy:
//   supabase functions deploy notify-event
//   supabase secrets set FCM_PROJECT_ID=... \
//                        FCM_SERVICE_ACCOUNT="$(cat service-account.json)" \
//                        NOTIFY_WEBHOOK_SECRET="$(openssl rand -hex 32)"
// The trigger that calls this is in the push migration rather than a dashboard
// webhook, so there is nothing to click: set notify_function_url and
// notify_webhook_secret in app_settings and it is wired.

import { importPKCS8, SignJWT } from "npm:jose@6";
import { createClient } from "jsr:@supabase/supabase-js@2";

/// Which kinds of thing can arrive here. The trigger already refuses the rest,
/// so this is the same list said twice on purpose: the filter in SQL is what
/// saves the fan-out, and this one is what stops an unexpected kind being
/// forwarded to every device as an unreadable wake.
type NotifiableKind = "entry" | "member_joined" | "member_left";

const NOTIFIABLE: readonly string[] = [
  "entry",
  "member_joined",
  "member_left",
];

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  // `id` is the EVENT's id. `subject_id` is what the event is about — an entry
  // for 'entry', a member for the member kinds — and is what the device fetches
  // and opens. `actor_id` is a member id, and is null for a change no member
  // can be attributed with, which a stranger arriving on an open link always
  // is.
  record:
    | {
      id: string;
      kind: NotifiableKind;
      subject_id: string | null;
      group_id: string;
      actor_id: string | null;
    }
    | null;
}

const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
const serviceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";
const webhookSecret = Deno.env.get("NOTIFY_WEBHOOK_SECRET") ?? "";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const HTTP_TIMEOUT = 10_000;

/// Cached across invocations: Edge Function isolates are reused, and the token
/// is valid for an hour. Minting one per webhook added a round trip to Google
/// on every expense anyone recorded, for no benefit.
let cachedToken: { value: string; expiresAt: number } | null = null;

/// Mints an OAuth token for the FCM v1 API from the service account.
///
/// jose handles the PKCS#8 parsing and base64url encoding. Doing it by hand
/// meant stripping PEM armour with regexes and running JSON through btoa, which
/// throws on any non-ASCII character and produces standard base64 where the JWT
/// spec requires base64url.
async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // A minute of slack, so a token cannot expire between here and the send.
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const account = JSON.parse(serviceAccountJson);
  const key = await importPKCS8(account.private_key, "RS256");

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
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  // Without this check a failed mint yields `undefined`, every send goes out as
  // `Bearer undefined`, and the 401s are invisible because nothing inspects
  // them. Failing loudly here is the difference between a broken deploy that
  // reports itself and one that silently stops notifying anybody.
  if (!response.ok) {
    throw new Error(
      `FCM token request failed: ${response.status} ${await response.text()}`,
    );
  }
  const body = await response.json();
  if (typeof body.access_token !== "string") {
    throw new Error("FCM token response carried no access_token");
  }

  cachedToken = {
    value: body.access_token,
    expiresAt: now +
      (typeof body.expires_in === "number" ? body.expires_in : 3600),
  };
  return cachedToken.value;
}

/// Whether a send failure means this registration is dead for good.
///
/// UNREGISTERED (404) always does. INVALID_ARGUMENT (400) is the trap: FCM
/// returns it both for a token it cannot parse AND for a malformed message, and
/// the two are told apart only by the `details` array. Since a fan-out sends an
/// identical payload to everyone, treating every 400 as a dead token means one
/// payload bug deletes every device in the group and each of those users has to
/// reinstall to recover.
function isDeadToken(status: number, body: unknown): boolean {
  if (status === 404) return true;
  if (status !== 400) return false;

  const details = (body as { error?: { details?: unknown[] } })?.error?.details;
  if (!Array.isArray(details)) return false;

  // A payload problem is reported as google.rpc.BadRequest with fieldViolations.
  // Only the FcmError detail describes the registration itself.
  return details.some(
    (detail) =>
      (detail as { "@type"?: string })?.["@type"] ===
        "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
      (detail as { errorCode?: string })?.errorCode === "INVALID_ARGUMENT",
  );
}

/// Constant-time comparison, so the shared secret cannot be recovered by
/// timing repeated requests.
function secretMatches(provided: string, expected: string): boolean {
  if (provided.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < provided.length; i++) {
    diff |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (request) => {
  // The webhook is the only legitimate caller. Without this, anyone holding the
  // publishable key — which is public by design — could drive the fan-out.
  if (!webhookSecret) {
    console.error("NOTIFY_WEBHOOK_SECRET is not set; refusing to run");
    return new Response("misconfigured", { status: 500 });
  }
  if (
    !secretMatches(request.headers.get("x-webhook-secret") ?? "", webhookSecret)
  ) {
    return new Response("forbidden", { status: 403 });
  }

  const payload: WebhookPayload = await request.json();
  // group_events, not entries: one row per thing that actually happened,
  // already deduped and already carrying who did it. Watching `entries` sent a
  // notification per payer and share row, and only ever for creations.
  if (
    payload.type !== "INSERT" || payload.table !== "group_events" ||
    !payload.record
  ) {
    return new Response("ignored", { status: 200 });
  }
  const record = payload.record;

  if (!NOTIFIABLE.includes(record.kind)) {
    return new Response("not a notifying kind", { status: 200 });
  }

  // Service role: tokens_for_group reads other people's tokens, which no
  // user-facing policy permits.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The actor is excluded rather than the author. On an edit they are usually
  // different people, and the author is precisely who needs to hear that
  // somebody changed their expense.
  const { data: targets, error } = await supabase.rpc("tokens_for_group", {
    p_group_id: record.group_id,
    p_actor_id: record.actor_id ?? null,
  });
  if (error) {
    console.error("tokens_for_group failed", error);
    return new Response("error", { status: 500 });
  }
  if (!targets?.length) return new Response("nobody to wake", { status: 200 });

  if (!projectId || !serviceAccountJson) {
    console.warn("FCM is not configured; skipping fan-out");
    return new Response("unconfigured", { status: 200 });
  }

  let token: string;
  try {
    token = await accessToken();
  } catch (cause) {
    console.error("could not mint an FCM access token", cause);
    return new Response("error", { status: 500 });
  }

  const stale: string[] = [];

  // allSettled, not all: one recipient's network failure must not abandon the
  // rest of the group half-notified.
  await Promise.allSettled(
    targets.map(async (target: { token: string; platform: string }) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          signal: AbortSignal.timeout(HTTP_TIMEOUT),
          body: JSON.stringify({
            message: {
              token: target.token,
              // Data-only. A `notification` block would make the OS draw its
              // own banner from server-formatted text, which is the thing this
              // design exists to avoid.
              data: {
                kind: record.kind,
                event_id: record.id,
                subject_id: record.subject_id ?? "",
                group_id: record.group_id,
              },
              android: { priority: "high" },
              webpush: { headers: { Urgency: "high" } },
            },
          }),
        },
      );

      if (response.ok) return;

      const body = await response.json().catch(() => null);
      if (isDeadToken(response.status, body)) {
        stale.push(target.token);
      } else {
        console.error("FCM send failed", response.status, JSON.stringify(body));
      }
    }),
  );

  if (stale.length) {
    await supabase.from("device_tokens").delete().in("token", stale);
  }

  return new Response("ok", { status: 200 });
});
