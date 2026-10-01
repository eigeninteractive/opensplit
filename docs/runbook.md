# Running OpenSplit: locally, in production, and the cutover

This file is the operational side of the project: how a branch is tested on
your own machine, how the production backend is stood up once, how `main`
moves from the old Supabase and Firebase Hosting stack to the Worker, and what
every release after that does.

Commands that change something in a Cloudflare, Google, Resend, GitHub or Play
account are in the production sections, and only there. Nothing in the
repository runs them for you, apart from the release workflow on a push to
`main`.

---

## Local and production are separate by construction

| | Local: `pnpm dev`, the test suites, CI | Production |
|---|---|---|
| Worker configuration | the `env.test` block of `server/wrangler.jsonc` | the top level of `server/wrangler.jsonc` |
| D1, KV, Durable Objects | files under `server/.wrangler/state` | your Cloudflare account |
| Secrets | `server/.dev.vars` (gitignored) | stored against the Worker; the first deploy, then `wrangler secret put` |
| Google sign-in | off: no client in `.dev.vars` | the Google OAuth web client |
| Sign-in codes | printed in the Worker's terminal | emailed by Resend |
| Push | skipped: no FCM credentials | sent through FCM |
| Rate limits | raised out of the way | the real ones |
| Web client's API | the page's origin, `http://localhost:8787` | the page's origin, the domain |
| Android client's API | `env/local.json`, passed last | `env/app.json` (from GitHub variables in CI) |

What keeps them apart:

- **`wrangler dev` is local.** It reaches the account only for a binding
  marked `remote: true` (none is) or a command run with `--remote`. Every
  package script that runs the Worker or migrates locally uses `--env test`.
- **The `test` environment keeps the placeholder ids, on purpose.** Even a
  mistaken `wrangler … --env test --remote` names a database that does not
  exist and fails, instead of reaching production.
- **The web client has no backend setting.** It talks to whatever origin
  served it, so a bundle opened at `localhost:8787` cannot reach production.
- **An Android build talks to whatever it was built with.** Given only
  `env/app.json`, a local build is a production client. For local testing,
  always pass `env/local.json` after it.
- **Debug and release Android builds share one app id.** Installing a local
  debug build over the Play build means uninstalling first, which deletes that
  install's local data, and the other way round.

What does touch production, and nothing else does: `wrangler deploy`,
`wrangler secret put`, `wrangler d1 create`, `wrangler kv namespace create`,
anything run with `--remote` (including `pnpm db:migrate:remote`), and
`wrangler tail`, which only reads.

---

## Testing a branch locally

### Once per machine

```sh
cd server                            # pnpm itself installed once: pnpm.io/installation
pnpm install                         # also fetches the Node that package.json pins
cp .dev.vars.example .dev.vars       # local secrets; the example's values work as they are
cd ..
cp env/local.example.json env/local.json
```

`env/app.json` is needed too (copy `env/app.example.json`). It holds only
public identifiers, and the production values are fine for local runs.

### Starting from a clean local state

Do this after pulling a branch that changes a migration, or whenever local data
gets in the way:

```sh
cd server
rm -rf .wrangler/state
pnpm db:migrate:local
```

The Durable Objects need no command: each one migrates itself the first time it
is opened.

### The web app

```sh
dart run tool/build_web.dart         # the whole front end, into build/web
cd server && pnpm dev                # the Worker, on localhost:8787
```

Open **`http://localhost:8787/app`**, with `localhost` rather than
`127.0.0.1`, because the session cookie and `APP_ORIGIN` in `.dev.vars` are for
`localhost`. Rebuild after changing Dart code; this path has no hot reload.

- **Signing in.** Continue as a guest, or use an email address: the code is
  printed in the `pnpm dev` terminal. Google sign-in has no credentials
  locally and fails.
- **Two people.** Use a second browser profile or a private window, since each
  has its own session and its own local database. An invite link made in one
  opens in the other, because the web mints links under its own origin.
- **Notifications** are not sent locally.

### Android: the emulator, then a phone

```sh
cd server && pnpm dev                # in one terminal

flutter run \
  --dart-define-from-file=env/app.json \
  --dart-define-from-file=env/local.json   # last, so its API_BASE_URL wins
```

`env/local.json` points at `http://10.0.2.2:8787`, which is this machine as
the emulator sees it. For a physical phone on the same Wi-Fi, change that to
this machine's LAN address (`ipconfig getifaddr en0` on a Mac), and start the
Worker with `pnpm dev --ip 0.0.0.0` so it accepts connections from the network.
Debug builds allow plain HTTP; release builds never do.

- **Signing in.** Guest and email code work. Google sign-in does not, for the
  same reason as on the web.
- **Invite links.** A link shared from a local Android build is minted under
  the production host (`LINK_HOST`), where the token means nothing. To test
  joining, open the link's `/app/join/<token>` path on the local web app, or
  join from the web and look at the result on the phone.
- **Switching to the Play build** means uninstalling the debug build first (see
  above).

### The automated suites

```sh
cd server && pnpm lint && pnpm typecheck && pnpm test   # Biome over the repo, then the Worker in workerd
cd .. && flutter test                                   # the client
```

The client's integration tests run against a real Worker and skip themselves
without one. With `pnpm dev` running:

```sh
flutter test --tags integration --dart-define=REQUIRE_BACKEND=true
```

---

## Production setup, once

### 0. Accounts and a login

- A Cloudflare account. The **Workers Free** plan is enough for the Worker,
  D1, KV and the SQLite-backed Durable Objects both classes declare. The one
  unknown is the rate-limit binding (`ratelimits` in `wrangler.jsonc`): its
  documentation does not say which plans include it, so the first deploy is
  where you find out.
- The zone **`eigeninteractive.com`** on Cloudflare, with Cloudflare as its
  authoritative nameservers. The Worker attaches a subdomain of it.

```sh
cd server
pnpm install
pnpm exec wrangler login
pnpm exec wrangler whoami            # confirm the right account before continuing
```

### 1. Create the D1 database and the KV namespace

These create real, empty resources in the account:

```sh
pnpm exec wrangler d1 create opensplit                # prints a database_id
pnpm exec wrangler kv namespace create opensplit-cache  # prints an id
```

The names are account-wide, unlike the `DB` and `CACHE` bindings the Worker
sees, so both carry the project's name. Put both ids into the **top level** of
`server/wrangler.jsonc`, replacing the placeholders, and commit them. They are not secrets: an id is useless without a
token for the account. Leave the `env.test` block's placeholders alone; they
are what keeps local runs from reaching these resources.

```sh
pnpm check:deploy-config             # "Deploying to real resources: DB, CACHE."
```

The release workflow runs the same check and refuses to deploy while either id
is still a placeholder, because Wrangler would otherwise bind to a database
that does not exist, pass the health check (which touches neither), and fail
on the first real request.

KV holds only derived, rebuildable things: a blob of exchange rates per month,
and the FCM access token. Losing it costs one cron run.

### 2. Google OAuth

In the **Google Cloud Console** for the project behind `FCM_PROJECT_ID`, under
*APIs & Services → Credentials*:

**The Web client** already exists from the Supabase era: keep it, since its id
is already in every build. Google never shows a client secret again after
creating it, so *Add secret* on the client for a new one, and disable the old
one after the cutover. Its id and secret are the `GOOGLE_CLIENT_ID` and
`GOOGLE_CLIENT_SECRET` secrets below, and its id is also `GOOGLE_WEB_CLIENT_ID`
in `env/app.json`. Add exactly one authorized redirect URI, and the origin:

```
https://opensplit.eigeninteractive.com/api/auth/callback/google
https://opensplit.eigeninteractive.com                           (JavaScript origin)
```

The path is Better Auth's (`basePath: "/api/auth"` in `server/src/auth.ts`) and
must match character for character, with no trailing slash. A wrong redirect
URI fails at Google's consent screen with `redirect_uri_mismatch`, before the
request reaches the Worker, so there is no trace of it in our logs.

**The Android client** must exist, bound to the package name
`com.eigeninteractive.opensplit` and to each signing certificate in
`site/.well-known/assetlinks.json`. Its id is never configured: Android mints
an ID token with the *web* client as its audience, which is the audience this
server verifies. The Android client exists only so Google will issue that token
to this app.

### 3. Resend

`support.eigeninteractive.com` is already a verified sending domain. Create an
API key scoped to sending only. The message and the sending address are in
`server/src/email/sender.ts`; the address is deliberately not configurable.

### 4. Firebase Cloud Messaging

The group's Durable Object calls the FCM v1 HTTP API directly, so what is
needed is a service account with the **Firebase Cloud Messaging API** enabled:
*Firebase console → Project settings → Service accounts → Generate new private
key.* The whole JSON file becomes `FCM_SERVICE_ACCOUNT`, and the `project_id`
inside it becomes `FCM_PROJECT_ID`. The Supabase era's key cannot be downloaded again; make a
new one, and delete the old one in *Google Cloud → IAM → Service accounts →
Keys* once the old stack is gone.

### 5. Exchange rates

The daily job runs Frankfurter (no key, the ECB's set) and then
exchangerate-api.com, which covers what the ECB does not: in practice AED,
VND, LKR, NPR, KWD and BHD. Its key is free; sign up at exchangerate-api.com
and keep the key for step 6. It is required like every other secret, so those
six currencies can never quietly go without rates.

### 6. Secrets

`secrets.required` in `server/wrangler.jsonc` names all seven, and every deploy
checks them: it refuses to go out while any is unset, so a forgotten one is a
failed release rather than a quietly broken feature. The values come from the
steps above:

| Secret | Value | If the value is wrong |
|---|---|---|
| `BETTER_AUTH_SECRET` | `openssl rand -base64 32` | Better Auth refuses to construct. Every request 500s. |
| `GOOGLE_CLIENT_ID` / `_SECRET` | step 2, the web client's pair | Google sign-in fails. Email codes and guests still work. |
| `RESEND_API_KEY` | step 3 | Resend rejects the send, so the code never arrives. |
| `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT` | step 4; the account is the whole JSON | Pushes fail and are logged. Deliberate: a notification must never stop an expense. |
| `EXCHANGERATE_API_KEY` | step 5 | The second rate provider fails; those six currencies get no rate that day. |

The Worker does not exist until its first deploy, and `wrangler secret put`
needs one to exist, so the first deploy carries all seven in a file (cutover
step 3). After that, change one at a time with `wrangler secret put`; see
*Rotating a secret*.

### 7. GitHub

In *Settings → Environments → `production`*:

**Secrets**

| Secret | Where from |
|---|---|
| `CLOUDFLARE_API_TOKEN` | *My Profile → API Tokens → Create Token*, from the **Edit Cloudflare Workers** template, plus *Account → D1 → Edit* (the release applies migrations), scoped to this account and the `eigeninteractive.com` zone |
| `CLOUDFLARE_ACCOUNT_ID` | *Workers & Pages → Overview*, in the right-hand column |
| `ANDROID_UPLOAD_*` | already set |

**Variables.** They become `env/app.json` at build time and are all public:

```
API_BASE_URL            https://opensplit.eigeninteractive.com
LINK_HOST               opensplit.eigeninteractive.com
GOOGLE_WEB_CLIENT_ID    …apps.googleusercontent.com
FCM_PROJECT_ID          FCM_SENDER_ID          FCM_VAPID_KEY
ANDROID_FCM_API_KEY     ANDROID_FCM_APP_ID
WEB_FCM_API_KEY         WEB_FCM_APP_ID
```

plus the Play ones that are already there (`PLAY_*`, `GCP_WORKLOAD_IDENTITY_PROVIDER`,
and `FIREBASE_PROJECT_ID`, which the Play step authenticates against).
`dart run tool/verify_config.dart` checks the shape of every value.

---

## The cutover: merging `cloudflare` into `main`

`main` still runs the Supabase backend and serves the site from Firebase
Hosting. There are no real users and no data to keep, so this is a replacement,
not a migration: nothing runs side by side, and nothing needs to stay
compatible.

1. **Do the production setup above**, steps 0 to 5, and push the commit with
   the real ids to the `cloudflare` branch.
2. **Free the domain.** In the Firebase console, *Hosting → the site → Custom
   domains*, remove `opensplit.eigeninteractive.com`. In Cloudflare, *DNS*,
   delete every record for `opensplit` that pointed at Firebase. A Custom
   Domain cannot be attached over an existing record, and the deploy says so.
3. **Deploy once by hand, from the branch, with the secrets.** This creates
   the Worker, its two cron triggers and the Custom Domain, which needs more
   permission than the CI token has; `wrangler login` has it. The secrets go
   in with it (step 6), from a file outside the repository that only you can
   read and that is deleted straight after.

   ```sh
   dart run tool/build_web.dart                       # with the production env/app.json
   cd server
   pnpm exec wrangler d1 migrations apply opensplit --remote
   umask 077 && secrets="$(mktemp)"
   "${EDITOR:-vi}" "$secrets"                         # NAME=value, one line for each secret in step 6
   pnpm exec wrangler deploy --secrets-file "$secrets"
   rm "$secrets"
   ```

   `FCM_SERVICE_ACCOUNT` is a whole JSON file, so put it on one line in single
   quotes, which keep the private key's `\n` escapes as they are:
   `FCM_SERVICE_ACCOUNT='<the output of jq -c . service-account.json>'`.

4. **Verify** (below). Production now works, and `main` has not changed yet.
5. **Configure GitHub** (step 7), and delete what belonged to the old stack:
   the `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
   `FIREBASE_DEPLOY_SERVICE_ACCOUNT` and `FIREBASE_HOSTING_SITE` variables.
6. **Open the pull request** from `cloudflare` to `main` and wait for CI: the
   analyse-and-test, backend, release-tooling and web-bundle jobs.
7. **Merge it** with a merge commit, as the history does. The release workflow
   then runs CI again, checks the resource ids, builds the web bundle and the
   signed Android bundle, applies D1 migrations (none pending after step 3),
   deploys the same code again, waits for `/api/health`, and sends the Android
   build to Play closed testing.
8. **Verify again**, then check Android App Links on a phone with the Play
   build (below). Testers who had the Supabase-era build installed get a fresh
   local database and sign in again; nothing from the old backend carries over.
9. **Point the old addresses here.** The two Firebase Hosting sites,
   `opensplit.web.app` and `opensplit-app.web.app` (and their
   `.firebaseapp.com` twins), are kept rather than deleted, and turned into
   permanent redirects to this domain, path and query intact. This waits
   until now because a 301 is cached by browsers: redirecting to a domain
   that is not serving yet would strand visitors on a dead address, and
   before the merge, `main`'s old release workflow would deploy over it.

   ```sh
   cd legacy-domains
   pnpm dlx firebase-tools@15.26.0 login               # once, if not logged in
   pnpm dlx firebase-tools@15.26.0 deploy --only hosting
   curl -sI https://opensplit.web.app/app/welcome      # 301, location: https://opensplit.eigeninteractive.com/app/welcome
   ```

   Nothing in CI deploys it; see `legacy-domains/README.md`.
10. **Decommission the old stack**: delete the Supabase project from its
    dashboard. Keep the Firebase project itself: FCM, the Google OAuth clients
    and the two redirecting sites live in it.

---

## Every release after that

A push to `main` runs `.github/workflows/release.yml`:

1. CI, the same jobs as on a pull request.
2. The resource-id check, before anything slow.
3. The web bundle and the signed Android bundle, uploaded as artifacts.
4. `wrangler d1 migrations apply opensplit --remote`: whatever is pending.
5. `wrangler deploy`: the script and the bundle, together, as one version.
6. A wait for `/api/health`, then Play closed testing.

D1 migrations are applied before the Worker that needs them goes live.
Before launch, a schema change needs no compatibility period; if one is
awkward, resetting the backend is simpler (`docs/resetting-the-backend.md`).
The Durable Objects migrate themselves, lazily, the first time each group is
opened after a deploy.

A manual run (*Actions → Release → Run workflow*) with **deploy** unchecked
builds the artifacts without deploying anything.

---

## Verify

```sh
base=https://opensplit.eigeninteractive.com

curl -s $base/api/health                       # {"ok":true,"service":"opensplit",...}
curl -sI $base/                                # 200, the landing page
curl -sI $base/privacy                         # 200, not a redirect
curl -sI $base/app/ | grep -i cross-origin     # both isolation headers
curl -sI $base/app/g/does-not-exist-yet        # 200 and text/html: the shell
curl -sI $base/.well-known/assetlinks.json     # 200 application/json, no redirect
curl -s "$base/api/reference" | head -c 200    # currencies and categories
```

`/api/health` proves the script deployed, not that D1 is bound, since it
touches no database. A guest sign-in does, writing a user and a session:

```sh
token=$(curl -s -X POST $base/api/identity/guest | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo "$token"                                  # non-empty: D1 and BETTER_AUTH_SECRET work
```

`D1_ERROR: no such database` instead means the id in `wrangler.jsonc` is wrong.

The exchange rates have no natural first request: the daily job fires at 04:00
UTC, and no command fires a production cron by hand. Ask for one day instead,
which runs the same provider waterfall and KV publish. It needs a session, so
reuse the guest's:

```sh
pnpm exec wrangler tail --format pretty &

curl -s -X POST $base/api/fx/backfill -H "Authorization: Bearer $token" \
  -H 'content-type: application/json' \
  -d "{\"asOf\":\"$(date -u -v-3d +%F)\",\"currency\":\"EUR\"}"   # {"accepted":true}

curl -s "$base/api/fx?since=$(date -u -v-7d +%F)" | head -c 300
```

In the tail, `[fx] stored N months …` means rates reached KV. `[fx] uncovered
after the waterfall AED,VND,LKR,NPR,KWD,BHD` is correct when
`EXCHANGERATE_API_KEY` is unset. The guest is removed by the daily sweep after
ninety days, or now:

```sh
pnpm exec wrangler d1 execute opensplit --remote \
  --command "delete from user where email like '%@anonymous.placeholder.invalid'"
```

---

## Android App Links

The intent filter claims `https://opensplit.eigeninteractive.com/app/*`, and
Android verifies it by fetching `/.well-known/assetlinks.json` from the live
host, so this can only be checked once the domain is serving:

```sh
adb shell pm verify-app-links --re-verify com.eigeninteractive.opensplit
adb shell pm get-app-links com.eigeninteractive.opensplit   # must say "verified"
```

Anything else means links open in a browser instead of the app, silently.
`site/.well-known/README.md` explains which certificates belong in that file.

## Play Console

Under *App content*, the three URLs, each a real static file answering 200 with
no redirect, and the same constants the app's Settings screen opens
(`lib/config.dart`):

```
https://opensplit.eigeninteractive.com/privacy
https://opensplit.eigeninteractive.com/terms
https://opensplit.eigeninteractive.com/delete-account
```

---

## Rotating a secret

```sh
pnpm exec wrangler secret put BETTER_AUTH_SECRET
```

Takes effect within seconds. Rotating `BETTER_AUTH_SECRET` **signs every
session out**, guests included, and a signed-out guest has lost the only key
to their account. Rotate it only after an actual exposure. The others are safe
to rotate at any time.

## Tearing it down

```sh
pnpm exec wrangler delete                                 # the Worker, and every Durable Object with it
pnpm exec wrangler d1 delete opensplit
pnpm exec wrangler kv namespace delete --namespace-id <id>
```

Deleting the Worker deletes the Durable Objects, which are where every group's
ledger lives. There is no undo. To start again with an empty backend rather than
remove it, see `docs/resetting-the-backend.md`.
