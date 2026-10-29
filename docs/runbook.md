# Running OpenSplit: locally and in production

This file is the operational side of the project: how a branch is tested on
your own machine, how the production backend is stood up once, and what every
release after that does.

Commands that change something in a Cloudflare, Google, Resend, GitHub or Play
account are in the production sections. After CI passes, pushes to `main`
deploy the web/backend; an app version change also submits to Play production.
A manual **Release** run deploys only when **deploy** is checked.

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
`localhost`. This path has no hot reload. After changing Dart code, stop
`pnpm dev`, rebuild, and start it again. The builder replaces `build/web`;
restarting Wrangler refreshes its asset manifest instead of retaining 404s for
the replaced files. If the browser offers an update, use **Restart** to switch
its service worker to the rebuilt release.

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

**The Web client**, an OAuth client of type *Web application*. Its id and
secret are the `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` secrets below, and
its id is also `GOOGLE_WEB_CLIENT_ID` in `env/app.json`, so it is in every
build: replace the secret, never the client. Google shows a secret only when it
is made, so a lost one is replaced by *Add secret* on the client, put in with
`wrangler secret put`, and then the old one disabled. Add exactly one
authorized redirect URI, and the origin:

```
https://opensplit.eigeninteractive.com/api/v1/auth/callback/google
https://opensplit.eigeninteractive.com                           (JavaScript origin)
```

The path uses `authBasePath`, derived from `apiBasePath` in `server/src/paths.ts`, and
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
inside it becomes `FCM_PROJECT_ID`. A key cannot be downloaded again, so a lost
one is replaced the same way: generate another, put it in, and delete the old
one in *Google Cloud → IAM → Service accounts → Keys*.

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
needs one to exist, so the first deploy carries all seven in a file (step 7).
After that, change one at a time with `wrangler secret put`; see *Rotating a
secret*.

### 7. The first deploy

`opensplit.eigeninteractive.com` must have no DNS record yet: a Custom Domain
cannot be attached over an existing one, and the deploy says so.

The first deploy is by hand, because it creates the Worker, its two cron
triggers and the Custom Domain, which needs more permission than the CI token
has; `wrangler login` has it. The secrets go in with it (step 6), from a file
outside the repository that only you can read and that is deleted straight
after.

```sh
dart run tool/build_web.dart                       # with the production env/app.json
cd server
pnpm exec wrangler d1 migrations apply opensplit --remote
umask 077 && secrets="$(mktemp)"
"${EDITOR:-vi}" "$secrets"                         # NAME=value, one line for each secret in step 6
pnpm exec wrangler deploy --env="" --secrets-file "$secrets"
rm "$secrets"
```

`FCM_SERVICE_ACCOUNT` is a whole JSON file, so put it on one line in single
quotes, which keep the private key's `\n` escapes as they are:
`FCM_SERVICE_ACCOUNT='<the output of jq -c . service-account.json>'`.

Then *Verify* (below).

### 8. GitHub

In *Settings → Environments → `production`*:

**Secrets**

| Secret | Where from |
|---|---|
| `CLOUDFLARE_API_TOKEN` | *My Profile → API Tokens → Create Token*, from the **Edit Cloudflare Workers** template, plus *Account → D1 → Edit* (the release applies migrations), scoped to this account and the `eigeninteractive.com` zone |
| `CLOUDFLARE_ACCOUNT_ID` | *Workers & Pages → Overview*, in the right-hand column |
| `ANDROID_UPLOAD_KEYSTORE_BASE64`, `_STORE_PASSWORD`, `_KEY_ALIAS`, `_KEY_PASSWORD` | the upload keystore, base64-encoded, and its passwords and alias |

**Variables.** They become `env/app.json` at build time and are all public:

```
API_BASE_URL            https://opensplit.eigeninteractive.com
LINK_HOST               opensplit.eigeninteractive.com
GOOGLE_WEB_CLIENT_ID    …apps.googleusercontent.com
FCM_PROJECT_ID          FCM_SENDER_ID          FCM_VAPID_KEY
ANDROID_FCM_API_KEY     ANDROID_FCM_APP_ID
WEB_FCM_API_KEY         WEB_FCM_APP_ID
```

plus `PLAY_DEPLOY_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, and
`FIREBASE_PROJECT_ID`, which the Play step authenticates against. Production's
track and full rollout status are fixed in the Fastlane production lane;
`PLAY_TRACK` and `PLAY_RELEASE_STATUS` only configure manual testing lanes.
Automatic releases use update priority 0. A manual Release run can explicitly
choose a different priority; the old `PLAY_UPDATE_PRIORITY` repository or
environment variable is not read by the workflow.
`dart run tool/verify_config.dart` checks the shape of every value.

From here on, a push to `main` deploys the web/backend. A changed app version
also submits an Android release to Play production.

---

## Every release

A push to `main` runs `.github/workflows/release.yml`:

1. CI, the same jobs as on a pull request, including the existing Cider
   version/changelog and Play release-note tests.
2. The resource-id check, before anything slow.
3. The build number and complete web bundle, uploaded as an artifact.
4. When the app version has no `v<version>` release tag, a signed Android bundle
   and Play metadata: release notes from `CHANGELOG.md` (see *Versions*) plus artwork.
   Android and web share the build number on these releases.
5. `wrangler d1 migrations apply opensplit --remote`: whatever is pending.
6. `wrangler deploy`: the script and the bundle, together, as one version.
7. A wait for `/api/health`, then, for a pending app version, a Play production
   submission with status `completed`, the notes and artwork. This requests full
   rollout subject to Google review and managed publishing. Fastlane skips
   unchanged images by checksum and preserves listing text.
8. A `v<version>` tag after an app release submission. This records that Play
   accepted the upload; it does not mean review is complete. Web-only deployments
   do not create app version tags.

The tag is the release-completion marker. If a newer web-only merge supersedes
the version-bump build, or an upload fails, that app version stays pending for
the next successful run. Otherwise an ordinary merge could lose the requested
Android release. Once tagged, subsequent merges skip Android until the next bump.

Documentation, website, cosmetic and dependency PRs do not need an app version
bump. They can merge without Android signing, an AAB build or a Play submission.
Shared Flutter UI changes still reach the web deployment; Android receives them
in the next versioned release. App dependencies and fixes can also accumulate
until a version bump intentionally publishes them.

The current-main check skips superseded commits when merges overlap. A green
upload means Play accepted the submission, not that review has finished or
users have installed it. Additional submissions during review can delay approval.

D1 migrations are applied before the Worker that needs them goes live.
The Durable Objects migrate themselves, lazily, the first time each group is
opened after a deploy. Keep backend/schema changes compatible with installed
clients throughout Play review, rollout and delayed installation. A breaking
API needs an explicit transition plan before merge; an urgent update priority
does not provide compatibility. Normal schema changes use incremental migrations;
an initial schema or testing-era storage reset must not replace production data.

A manual run (*Actions → Release → Run workflow*) with **deploy** unchecked
builds web and Android artifacts without deploying anything. Checking **deploy**
deploys the web/backend and submits Android only if the app version is still
untagged.

---

## Dependency updates

Dependabot opens one weekly `routine-dependencies` pull request across the
Flutter app, generated API package, Worker, service worker, GitHub Actions and
Fastlane. Minor and patch updates share the full CI matrix and one merge to
`main`, which deploys the web/backend. Bump the app version in the dependency PR
when its changes should also ship to Android. Grouping does not enable automatic
merging.
The configuration is in [`.github/dependabot.yml`](../.github/dependabot.yml);
see GitHub's [multi-ecosystem grouping documentation](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configuring-multi-ecosystem-updates).

Major upgrades are excluded from the routine batch and assessed manually.
Read the release notes even for patch updates: authentication changes can
affect sign-ins in progress, and native plugins can raise build requirements.
Drizzle's next 1.0 release candidates are held for an explicit database review;
update the ORM and migration tool together when that review is complete.
Security updates can arrive separately from the weekly batch, so an urgent
fix does not wait for a scheduled maintenance release.
The [upstream workaround review](upstream-workarounds.md) records fixes and
remaining constraints found in the app's source comments.

Before merging a dependency batch, regenerate the files affected by it and
review the diff. For Wrangler, run `pnpm cf-typegen` in `server/`. For Drift,
refresh its generated contracts and run `dart run tool/update_drift_web_assets.dart`
from the root. CI checks these outputs, the API client, the server schemas and
migrations, native tests, Chrome/WASM database tests, and the web bundle.
An Android plugin update also needs an Android release build and device checks
for the behaviour it changes; the PR's web build cannot establish that.

## Versions

A build has two numbers, and only one of them is written down.

- **The version**, `1.2.0`: what people see, and what the changelog is
  organised by. It is `version:` in `pubspec.yaml`, changed only through
  [cider](https://pub.dev/packages/cider), which keeps `CHANGELOG.md` in step.
- **The build number**, `1701`: what Play orders builds by, Android's
  `versionCode`. It is never written down. The release workflow works it out
  and gives the same number to web and Android on app releases. A web-only
  deployment advances the web build number while Android keeps its last release.

cider is a dev dependency, so `dart run cider` is the version `pubspec.lock`
pins, the same everywhere.

### In every pull request

Changes intended for the next app release get an entry under *Unreleased*:

```sh
dart run cider log fixed 'Totals no longer round twice.'
# or added, changed, deprecated, removed, security
```

Write it for a user: the lines become the release's notes in Play. Documentation
and standalone website changes need no app changelog entry or version bump.

### Cutting a version

When ready to publish Android, bump and finalize the version in a PR:

```sh
dart run cider bump minor      # or patch, or major
dart run cider release         # Unreleased becomes this version's section, dated today
dart run tool/store_artifacts.dart
```

The artwork provenance includes `pubspec.yaml`, so regenerate after every
version bump. This refreshes its manifest and any date-dependent screenshot data.

Both files go in the PR. The existing release-note tests check that Cider can
read a section for the current version and produce nonempty Play-compatible
notes. The release workflow reads the version with Cider and checks for its
release tag before building Android. Use the normal Cider bump commands to
advance the version; semantic bump size remains a review decision.

Which part to bump: patch when a version only fixes things, minor when it adds
anything, and major when it leaves older clients behind, such as a server change
they can no longer talk to. Send a breaking release with update priority 4 so
eligible clients request an immediate update when Play makes it available.
Priority does not replace the pause or verify that everyone has installed it.

Merges without a version bump keep the app version name. An app release or
manual artifact build receives its own build number; CI does not create
version-changing commits or push to `main`.

### What a release does with them

**Play's notes.** `tool/release_notes.dart` takes the *Unreleased* entries,
since they are what this build has that the last version did not. Straight
after a version is cut there are none, and it takes that version's section
instead. It drops the headings and the Markdown, which Play would show
literally, and keeps whole entries up to Play's 500 characters, counting the
rest on a last line. The notes are in `en-US`, the store listing's language,
because Play refuses notes in a language the listing lacks. Add a language to
the listing, and the workflow has to write that language too.

**Play's artwork.** First run `dart run tool/store_artifacts.dart` to refresh
screenshots, the feature graphic and their derivatives together. CI runs its
`--check` mode and rejects stale sources or outputs. `tool/play_metadata.dart` packages the notes and the current
committed artwork into a fresh `en-US` supply tree. It checks all inputs before
writing, resizes the icon to 512 × 512 and retains the feature graphic and
screenshots byte-for-byte. The workflow passes that directory as
`PLAY_METADATA_DIR`; the lane refuses incomplete artwork. See
`docs/brand/README.md` for the source files and generation commands. Run
`bundle exec ruby test/tool/fastlane_test.rb` to exercise the upload configuration
locally without contacting Play.

**Tags.** The first successful submission of each version tags its commit
`v1.2.0`, and retries leave the tag where it was. The compare links at the foot of
`CHANGELOG.md` point at those tags. `v1.0.0` marks the first build that reached
Play.

### The build number

Run number × 100, plus the attempt: release run 17 is build 1701, and its
retry is 1702. Numbering builds in CI rather than in the repository is the
usual arrangement. A number in `pubspec.yaml` has to be raised by a commit,
and two pull requests then race for it. The run number only goes up, and the
attempt gives a retry a new number, which Play insists on even for the same
commit. Play's ceiling, 2,100,000,000, is twenty-one million runs away.

Two other schemes were passed over. The commit count needs the whole history
in every checkout, and a retry would reuse the number. Asking Play for the
highest code so far couples every build to the API being reachable.

**What would break it:** GitHub numbers runs per workflow file. Rename or
recreate `release.yml` and the count starts again at 1, below every code Play
has seen, so every upload is refused. If it ever has to be renamed, add an
offset above the last run number to the formula in the *Number this build*
step.

---

## Verify

```sh
base=https://opensplit.eigeninteractive.com
api_base="$base/api/v1"  # current contract base; server/src/paths.ts owns it

curl -s $base/api/health                       # {"ok":true,"service":"opensplit",...}
curl -sI $base/                                # 200, the landing page
curl -sI $base/privacy                         # 200, not a redirect
curl -sI $base/app/ | grep -i cross-origin     # both isolation headers
curl -sI $base/app/g/does-not-exist-yet        # 200 and text/html: the shell
curl -sI $base/.well-known/assetlinks.json     # 200 application/json, no redirect
curl -s "$api_base/reference" | head -c 200    # currencies and categories
```

`/api/health` proves the script deployed, not that D1 is bound, since it
touches no database. A guest sign-in does, writing a user and a session:

```sh
token=$(curl -s -X POST $api_base/identity/guest | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo "$token"                                  # non-empty: D1 and BETTER_AUTH_SECRET work
```

`D1_ERROR: no such database` instead means the id in `wrangler.jsonc` is wrong.

The exchange rates have no natural first request: the daily job fires at 04:00
UTC, and no command fires a production cron by hand. Ask for one day instead,
which runs the same provider waterfall and KV publish. It needs a session, so
reuse the guest's:

```sh
pnpm exec wrangler tail --format pretty &

curl -s -X POST $api_base/fx/backfill -H "Authorization: Bearer $token" \
  -H 'content-type: application/json' \
  -d "{\"asOf\":\"$(date -u -v-3d +%F)\",\"currency\":\"EUR\"}"   # {"accepted":true}

curl -s "$api_base/fx?since=$(date -u -v-7d +%F)" | head -c 300
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

The release service account needs the app-level
[Manage store presence](https://support.google.com/googleplay/android-developer/answer/9844686)
permission as well as access to release on testing tracks, so Fastlane can
update the listing artwork. For automatic production submissions, also grant
**Release to production, exclude devices, and use Play App Signing** under
**Play Console → Users and permissions → CI service account → App permissions →
OpenSplit**. Use the account named by `PLAY_DEPLOY_SERVICE_ACCOUNT`.

Complete outstanding production setup and country selection before merging the
switch to production. In **Publishing overview**, turn **Managed publishing**
off for approved changes to publish automatically. Review pending changes first:
merging the production workflow can initiate the public launch. First production
releases have no percentage rollout; this workflow also requests 100% for updates.
Review or setup failures stay visible instead of silently saving an unsubmitted
release. The upload does not change listing text.

The `closed` and `internal` Fastlane lanes remain available for manual testing;
their track/status overrides cannot redirect the production lane. Testing uploads
can still change the shared store artwork. Halting production stops further
distribution but leaves installed copies in place; fixes need a higher build code.

Verify the feature graphic under **Grow users → Store presence → Main store
listing → Graphics** after uploading and publishing. Its presence there is
separate from its visibility on a particular public listing: Google uses it as
the preview-video cover and on selected promotional surfaces. A missing public
banner alone does not establish an upload failure. See
[Google's preview asset guidance](https://support.google.com/googleplay/android-developer/answer/9866151).

Under *App content*, the three URLs, each a real static file answering 200 with
no redirect, and the same constants the app's Settings screen opens
(`lib/config.dart`):

```
https://opensplit.eigeninteractive.com/privacy
https://opensplit.eigeninteractive.com/terms
https://opensplit.eigeninteractive.com/delete-account
```

---

## The old addresses

`opensplit.web.app` and `opensplit-app.web.app` are Firebase Hosting sites that
301 to this domain, path and query intact, for the links and App Links that
earlier builds minted under them. Their configuration and the command that
redeploys them are in `legacy-domains/README.md`; nothing in CI touches them.

Keep the Firebase project, then, though the app is no longer hosted there:
FCM, the Google OAuth clients and those two sites all live in it.

---

## Rotating a secret

```sh
pnpm exec wrangler secret put BETTER_AUTH_SECRET --env=""
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
