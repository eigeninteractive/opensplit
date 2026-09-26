# Standing OpenSplit up on Cloudflare

Every command in this file changes something in a Cloudflare, Google, Resend or
Play account. Nothing in the repository runs any of them, and nothing in the
repository authenticates to those accounts: the whole backend is built and
tested against `wrangler dev`, which keeps its D1, KV and Durable Objects in
local files under `server/.wrangler/`. That is a deliberate boundary, and it has
a cost worth stating up front.

**Account-level mistakes cannot surface until you run this.** A missing secret,
a redirect URI that was never registered, a domain that is not attached — none
of those can fail in CI, because CI never reaches an account. What the code does
instead is fail loudly on each of them at the first request that needs it,
rather than half-working. Where it does that is noted below, step by step.

Run the steps in order. Several produce an identifier that the next step needs.

---

## 0. Before anything

- A Cloudflare account. The **Workers Free** plan is enough: SQLite-backed
  Durable Objects are on it, and both classes here declare
  `"storage": "sqlite"`. (The key-value storage backend is Paid-only, and is
  also the legacy one — nothing here uses it.) The free tier's daily limits are
  the thing to watch, not the plan.
- The zone **`eigeninteractive.com`** already on Cloudflare, with Cloudflare as
  its authoritative nameservers. The Worker attaches a subdomain of it.
- Node 24 and a checkout of this repository.

```sh
cd server
npm ci
npx wrangler login
npx wrangler whoami        # confirm the right account before continuing
```

`wrangler login` opens a browser and stores an OAuth token in your home
directory. If you have more than one Cloudflare account, `whoami` is the step
that stops you from creating a database in the wrong one.

---

## 1. Create the D1 database

```sh
npx wrangler d1 create opensplit
```

It prints a `database_id`. Put it in `server/wrangler.jsonc`, replacing the
placeholder:

```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "opensplit",
    "database_id": "00000000-0000-0000-0000-000000000000",  // <- replace this
    "migrations_dir": "migrations"
  }
],
```

The placeholder is not a secret and neither is the real id; it identifies a
database that only an authenticated account holder can reach. Commit it.

**Why the id is not discovered at deploy time:** `wrangler` resolves bindings
from the config file, not from the account, so a deploy with the placeholder
still binds — to nothing that exists. The first query fails at runtime with
`D1_ERROR: no such database`. That is the loud failure, and it is at request
time rather than deploy time, so check step 6's verification.

---

## 2. Create the KV namespace

```sh
npx wrangler kv namespace create CACHE
```

It prints an `id`. Same treatment:

```jsonc
"kv_namespaces": [{ "binding": "CACHE", "id": "0000000000000000000000000000000f" }],
```

This namespace holds only derived, rebuildable things — a blob of exchange rates
per month, and the FCM access token. Losing it costs one cron run.

---

## 3. Apply the database migrations

```sh
npx wrangler d1 migrations apply opensplit --remote
```

`--remote` is the whole point of the command; without it you have migrated the
local file again. It prints the migrations it is about to run and asks for
confirmation.

The Durable Objects are **not** migrated here and there is no command that does
it. Each object carries its own schema and applies whatever it has not yet run
on first open after a deploy, inside `blockConcurrencyWhile`. That means a
schema change ships with the Worker script and lands per group, lazily, the
first time somebody touches that group.

---

## 4. Set the secrets

Each of these prompts for a value and stores it encrypted against the Worker.
None of them appears in any file in this repository.

```sh
npx wrangler secret put BETTER_AUTH_SECRET     # openssl rand -base64 32
npx wrangler secret put GOOGLE_CLIENT_ID       # from step 5
npx wrangler secret put GOOGLE_CLIENT_SECRET   # from step 5
npx wrangler secret put RESEND_API_KEY         # from step 6
npx wrangler secret put FCM_PROJECT_ID         # from step 7
npx wrangler secret put FCM_SERVICE_ACCOUNT    # from step 7, the whole JSON
npx wrangler secret put EXCHANGERATE_API_KEY   # optional, from step 8
```

`server/.env.types` lists exactly these names and no values. It exists so that
`wrangler types` generates the same `Env` on a laptop as in CI, and it is the
list to check against if you are ever unsure whether a secret is still read.

Three of them fail quietly rather than loudly, by design, and it is worth
knowing which:

| Missing | What happens |
|---|---|
| `BETTER_AUTH_SECRET` | Better Auth refuses to construct. Every request 500s. Loud. |
| `GOOGLE_CLIENT_ID` / `_SECRET` | Google sign-in fails at the callback. Email codes and guest sessions still work. |
| `RESEND_API_KEY` | **Codes are written to the log instead of emailed.** A warning is logged on construction. Sign-in by email appears broken to the user with nothing in the response to say why. |
| `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT` | **Push is skipped silently.** Everything else works. This is deliberate: a notification that cannot be sent must never stop an expense being recorded. |
| `EXCHANGERATE_API_KEY` | The second rate provider skips itself. The first covers about ten of the sixteen currencies; the rest simply have no rate. |

`FCM_SERVICE_ACCOUNT` is the entire service-account JSON file as one value,
newlines in the private key included. Paste it at the prompt rather than
echoing it into the command, so it does not enter your shell history.

---

## 5. Google OAuth

In the **Google Cloud Console** for the project behind `FCM_PROJECT_ID`, under
*APIs & Services → Credentials*:

**The Web client** — this is the one whose id and secret go into step 4, and
whose id is also `GOOGLE_WEB_CLIENT_ID` in `env/app.json`. Add exactly one
authorized redirect URI:

```
https://opensplit.eigeninteractive.com/api/auth/callback/google
```

That path is Better Auth's, derived from `basePath: "/api/auth"` in
`server/src/auth.ts`. It is not configurable per-deployment and must match
character for character, including the absence of a trailing slash.

Also add the origin under *Authorized JavaScript origins*:

```
https://opensplit.eigeninteractive.com
```

**The Android client** must exist, bound to the package name
`com.eigeninteractive.opensplit` and to each signing certificate in
`site/.well-known/assetlinks.json`. Its id is never configured anywhere: Android
mints an ID token with the *web* client as its audience, because that is the
audience this server verifies. The Android client exists only so that Google
will issue that token to this app.

**If the redirect URI is wrong**, Google refuses at the consent screen with
`redirect_uri_mismatch` before the user ever reaches this server, so there is
nothing in the Worker's logs. That is the one failure in this document with no
trace on our side.

---

## 6. Resend

`support.eigeninteractive.com` is already a verified sending domain. Create an
API key scoped to sending only, and use it in step 4.

The message itself is in `server/src/email/sender.ts` — an eight-digit code,
not a magic link. If you change the sending address, change it there too; it is not
configurable, because an address that can be set wrong at deploy time is an
address that silently sends from a domain with no SPF record.

---

## 7. Firebase Cloud Messaging

Push is sent by the group's own Durable Object, calling the FCM v1 HTTP API
directly. There is no Firebase Admin SDK involved, so what is needed is a
service account with the **Firebase Cloud Messaging API** enabled:

*Firebase console → Project settings → Service accounts → Generate new private
key.* That downloads a JSON file. Its whole contents become
`FCM_SERVICE_ACCOUNT`, and `project_id` from inside it becomes
`FCM_PROJECT_ID`.

The Worker mints its own OAuth access token from that key with `jose`, and
caches it in KV under one key for every group object to share — otherwise a
hundred groups notified at once would mint a hundred tokens.

---

## 8. Exchange rates (optional)

The daily rate job runs two providers in order: Frankfurter, which needs no key
and publishes the ECB's set, and exchangerate-api.com, which needs a free key
and covers the currencies the ECB does not — in practice AED, VND, LKR, NPR,
KWD and BHD.

Without the key those six currencies have no rate. Amounts in them are still
recorded exactly; they just cannot be shown converted.

---

## 9. Build the front end and deploy

The Worker serves the API *and* the whole front end from one origin, and they
deploy together as one version. So the bundle has to exist first:

```sh
cd ..                       # repository root
dart run tool/build_web.dart
cd server
npx wrangler deploy
```

`wrangler deploy` uploads the script and the contents of `../build/web`, creates
both cron triggers, and attaches the custom domain declared in
`wrangler.jsonc` — creating the DNS record and issuing the certificate.

Two things can go wrong here and both are loud:

- **`../build/web` does not exist.** Wrangler refuses to start at all. Run the
  build. (For server-only work, `dart run tool/build_web.dart --site-only`
  produces the static root in about a second and needs no Flutter toolchain —
  but do not deploy that; it has no `/app`, and says so when it finishes.)
- **`opensplit.eigeninteractive.com` already has a DNS record.** A Custom Domain
  cannot be created over an existing CNAME. Delete the record first.

The deploy prints the version id and the domain. `workers.dev` is off, so there
is no second address: this Worker is reachable at one hostname or none. That is
not tidiness — the client is local-first, and its database, its session and its
service-worker registration are all keyed to the origin, so a person who opened
the app on a second origin would get a second, silently separate copy of their
own data.

---

## 10. Verify

```sh
base=https://opensplit.eigeninteractive.com

curl -s $base/api/health                       # {"ok":true,"service":"opensplit",...}
curl -sI $base/                                # 200, the landing page
curl -sI $base/privacy                         # 200, not a redirect
curl -sI $base/app/ | grep -i cross-origin     # both isolation headers
curl -sI $base/app/g/does-not-exist-yet        # 200 and text/html: the shell
curl -sI $base/.well-known/assetlinks.json     # 200 application/json, no redirect
curl -s "$base/api/reference" | head -c 200    # 16 currencies, 20 categories
```

`/api/health` answering proves the script deployed. It does **not** prove D1 is
bound correctly, because it touches no database. The cheapest request that does
is a guest sign-in, which writes a user and a session:

```sh
curl -s -X POST $base/api/identity/guest
```

A body carrying `"isAnonymous":true` and a non-null `token` means D1 is real and `BETTER_AUTH_SECRET` is set. `D1_ERROR: no such database`
means step 1's id did not make it into the config.

That leaves one guest account behind. It is collected by the weekly sweep after
ninety days, or you can delete the row now:

```sh
npx wrangler d1 execute opensplit --remote \
  --command "delete from user where email like '%@anonymous.placeholder.invalid'"
```

Then the exchange rates, which are the one part with no natural first request:
the daily job fires at 04:00 UTC and there is no `wrangler` command that fires a
production cron by hand. Rather than wait, ask for a specific day, which runs
the same provider waterfall and the same KV publish:

```sh
npx wrangler tail --format pretty &

curl -s -X POST $base/api/fx/backfill -H 'content-type: application/json' \
  -d "{\"asOf\":\"$(date -u -v-3d +%F)\",\"currency\":\"EUR\"}"   # {"accepted":true}

curl -s "$base/api/fx?since=$(date -u -v-7d +%F)" | head -c 300
```

In the tail, `[fx] stored N months …` is the line that says rates reached KV.
`[fx] uncovered after the waterfall AED,VND,LKR,NPR,KWD,BHD` is *correct* output
when `EXCHANGERATE_API_KEY` is unset — those are precisely the six the ECB does
not publish. `{"accepted":false}` means the day is already covered or was asked
for within the hour, both of which are ordinary.

The nightly run then proves itself the next morning: the same `/api/fx` call
should come back with a later date in it.

---

## 11. Android App Links

The intent filter in `AndroidManifest.xml` claims
`https://opensplit.eigeninteractive.com/app/*`, and Android verifies that claim
by fetching `/.well-known/assetlinks.json` from the live host. Nothing about
this can be tested before the domain is serving.

```sh
adb shell pm verify-app-links --re-verify com.eigeninteractive.opensplit
adb shell pm get-app-links com.eigeninteractive.opensplit
```

The second must report `verified` for the domain. Anything else means links open
in a browser instead of the app, silently, with no error anywhere in the app.

`site/.well-known/README.md` explains which certificates have to be in that file
and why all four of them do. Read it before assuming the list is complete.

---

## 12. Play Console

Under *App content*, the three URLs are:

```
https://opensplit.eigeninteractive.com/privacy
https://opensplit.eigeninteractive.com/terms
https://opensplit.eigeninteractive.com/delete-account
```

Each is a real static file at exactly that address, answering 200 with no
redirect — which matters, because a reviewer following a redirect chain to a
policy page is a reason for rejection, and because these are the same constants
the app's own Settings screen launches (`lib/config.dart`).

---

## 13. GitHub Actions

The release workflow deploys the Worker and the bundle in one step. It needs two
repository secrets:

| Secret | Where from |
|---|---|
| `CLOUDFLARE_API_TOKEN` | *Account API tokens → Create Token → Edit Cloudflare Workers*, scoped to this account and to the `eigeninteractive.com` zone |
| `CLOUDFLARE_ACCOUNT_ID` | *Workers & Pages → Overview*, in the right-hand column |

The **Edit Cloudflare Workers** template is enough for ordinary deploys, but
only because the first deploy — the one that creates the Worker and attaches the
Custom Domain — is the one you run by hand in step 9. Creating a Worker needs
Workers Admin, and attaching a Custom Domain needs *Zone → Workers Routes →
Write* for the zone. Do that once, interactively, and CI never needs either.

And these repository **variables**, which become `env/app.json` at build time
and are all public identifiers that ship inside the client:

```
API_BASE_URL            https://opensplit.eigeninteractive.com
LINK_HOST               opensplit.eigeninteractive.com
GOOGLE_WEB_CLIENT_ID    …apps.googleusercontent.com
FCM_PROJECT_ID          FCM_SENDER_ID          FCM_VAPID_KEY
ANDROID_FCM_API_KEY     ANDROID_FCM_APP_ID
WEB_FCM_API_KEY         WEB_FCM_APP_ID
```

`dart run tool/verify_config.dart` checks the shape of every one of them —
structure rather than emptiness, because a placeholder can look like a real
value and did.

---

## Rotating a secret

```sh
npx wrangler secret put BETTER_AUTH_SECRET
```

Overwriting takes effect on the next deploy or within seconds on the running
version. Rotating `BETTER_AUTH_SECRET` **signs every existing session out**,
including guests — and a guest who is signed out has lost the only key to their
ledger, because there is no email on the account to sign back in with. Rotate it
only in response to an actual exposure, and expect that consequence.

The others are safe to rotate at any time.

## Tearing it down

```sh
npx wrangler delete                                 # the Worker, and with it every Durable Object
npx wrangler d1 delete opensplit
npx wrangler kv namespace delete --namespace-id <id>
```

Deleting the Worker deletes the Durable Objects, which are where every group's
ledger actually lives. D1 holds only the index and the accounts. There is no
undo and no export; if you want the data, take it first.
