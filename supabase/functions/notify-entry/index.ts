// Fan-out for entry inserts: wake the other members' devices.
//
// Triggered by a database webhook on `entries`. It sends a data-only FCM
// message carrying nothing but ids — no amounts, no names, no description.
//
// Two reasons for that. First, the client has to pull the delta anyway to stay
// consistent, so anything included here would be a second source of truth.
// Second, formatting the text server-side would mean reimplementing currency
// exponents, rounding and each recipient's share outside Dart, where it would
// drift from the app silently. The device already knows how to say it.
//
// Deploy: supabase functions deploy notify-entry
// Then add a database webhook on entries (INSERT) pointing at it.

import { createClient } from 'jsr:@supabase/supabase-js@2';

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE';
  table: string;
  record: { id: string; group_id: string; created_by: string } | null;
}

const projectId = Deno.env.get('FCM_PROJECT_ID') ?? '';
const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';

/// Mints a short-lived OAuth token for the FCM v1 API from the service account.
async function accessToken(): Promise<string> {
  const account = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const encode = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const unsigned = `${encode(header)}.${encode(claims)}`;

  const pem = account.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${encodedSignature}`,
    }),
  });
  const body = await response.json();
  return body.access_token;
}

Deno.serve(async (request) => {
  const payload: WebhookPayload = await request.json();
  if (payload.type !== 'INSERT' || payload.table !== 'entries' || !payload.record) {
    return new Response('ignored', { status: 200 });
  }

  // Service role: tokens_for_entry reads other people's tokens, which no
  // user-facing policy permits.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: targets, error } = await supabase.rpc('tokens_for_entry', {
    p_entry_id: payload.record.id,
  });
  if (error) {
    console.error('tokens_for_entry failed', error);
    return new Response('error', { status: 500 });
  }
  if (!targets?.length) return new Response('nobody to wake', { status: 200 });

  if (!projectId || !serviceAccountJson) {
    console.warn('FCM is not configured; skipping fan-out');
    return new Response('unconfigured', { status: 200 });
  }

  const token = await accessToken();
  const stale: string[] = [];

  await Promise.all(
    targets.map(async (target: { token: string; platform: string }) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: target.token,
              // Data-only. A `notification` block would make the OS draw its
              // own banner from server-formatted text, which is the thing this
              // design exists to avoid.
              data: {
                kind: 'entry',
                entry_id: payload.record!.id,
                group_id: payload.record!.group_id,
              },
              android: { priority: 'high' },
              webpush: { headers: { Urgency: 'high' } },
            },
          }),
        },
      );

      // 404 UNREGISTERED / 400 INVALID_ARGUMENT mean the token is dead. Left in
      // place they accumulate forever and every send retries them.
      if (response.status === 404 || response.status === 400) {
        stale.push(target.token);
      }
    }),
  );

  if (stale.length) {
    await supabase.from('device_tokens').delete().in('token', stale);
  }

  return new Response('ok', { status: 200 });
});
