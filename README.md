# OpenSplit

Split expenses with friends. Free forever, no ads, works offline, open source.

OpenSplit is a local-first expense splitter for Android and the web. It exists
because every alternative either paywalls the act of logging an expense or has
no real mobile app.

**Status: in development.** Not yet released.

## What makes it different

- **Logging an expense is never gated.** No caps, no limits, no upsell. See
  [PRINCIPLES.md](PRINCIPLES.md).
- **Every read is instant.** The full journal lives on your device; balances,
  search and analytics are local SQL. No screen waits on a network.
- **Genuinely offline.** Full create/read/update/delete with no connection,
  indefinitely. Trips abroad are the main use case, not an edge case.
- **Multi-currency is core.** Balances are always per currency, never silently
  netted across one.
- **Your records do not depend on us.** The server stores rows and enforces one
  invariant; it computes nothing. The whole journal lives on your device, in
  plain SQLite, and exports to CSV. The hosted backend runs on Cloudflare
  Durable Objects, which you cannot stand up yourself — so
  [PRINCIPLES.md](PRINCIPLES.md) #6 says that plainly rather than promising a
  self-host path that does not exist.

## Architecture in one paragraph

A Flutter client (Riverpod, Drift, go_router) holds the entire journal in
SQLite and does all computation locally — split arithmetic, the balance fold,
debt simplification, analytics. The backend is a Cloudflare Worker behind a
Dart repository interface: one Durable Object per group, which is that group's
only writer and therefore the thing that can hand out a strictly increasing
sequence number, enforce `sum(payers) = sum(shares) = amount` in ordinary code,
and answer "are you a member" by reading its own table. D1 holds the handful of
facts that are genuinely cross-group — profiles, which groups somebody is in,
where to wake them, and what a link token points at. Reads outnumber writes
roughly 50:1, so putting reads on devices people already own is what makes
"free forever" credible rather than aspirational.

## Development

Requires the Flutter SDK and Node.

```bash
flutter pub get
dart run build_runner build        # Drift, Freezed and Riverpod codegen
flutter test                       # domain, storage, sync and UI flow tests
flutter run
```

The local backend:

```bash
dart run tool/build_web.dart --site-only   # the Worker serves a front end too
cd server
npm ci
npm run db:migrate:local           # applies server/migrations to local D1
npm run dev                        # the real Worker, on 127.0.0.1:8787
npm test                           # the Durable Object and the routes
```

`wrangler dev` runs the real Worker over local D1, KV and Durable Object
storage. Nothing it does touches a Cloudflare account, and it needs no
credentials beyond `cp .dev.vars.example .dev.vars`.

The first line is there because the Worker serves the site and the client as
well as the API, and it refuses to start at all without an assets directory.
`--site-only` builds the static root in about a second and skips the Flutter
client; drop the flag when you want `/app` too. `npm test` needs neither — the
server suite serves a three-file fixture it owns, so it never depends on which
build ran last.

The server tests are not optional decoration. They cover the balance invariant
rejecting an expense that does not add up, that a stale edit is refused only
when applying it would move money, that entries cannot be hard-deleted, that an
invite token can be spent exactly once by somebody with no other access to the
group, and that a collected group answers everybody with a tombstone rather
than refusing every device that still holds a copy.

They also cover what one member of a group can do to another, which is a
different question from what a stranger can do and has a much less obvious
answer: that an ordinary member cannot blank somebody's account link and evict
them, cannot remove a co-member who still owes or is owed, and — the one that
moves real money — cannot rewrite another member's UPI handle so a settle-up
handoff pays the wrong person.

This is the part the object model made ordinary. In Postgres the same rules
needed a deferred constraint trigger, a `SECURITY DEFINER` helper to stop
`is_group_member` recursing through its own policy, and a `guard_member_update`
trigger for the column rules — because an RLS policy chooses rows, cannot say
"this column, but only on your own row", and its `WITH CHECK` cannot see the
old row at all. A Durable Object runs one thing at a time and owns exactly one
group's rows, so all three become function calls with the before-and-after
values in hand.

```bash
dart run tool/build_web.dart                           # the whole front end
cd server && npm run db:migrate:local && npm run dev   # in one terminal
flutter test test/data/cloudflare_integration_test.dart
```

The full build and not `--site-only`, because this suite also asserts that a
cold deep link into `/app` arrives cross-origin isolated — which is a fact
about the Worker and the asset router together, and the only place it is
checked.

That runs the real adapter against a local `wrangler dev` — the actual Worker,
over local D1, KV and Durable Object storage. Nothing in it touches a
Cloudflare account and it needs no credentials.

It skips itself when nothing is listening, so `flutter test` stays green
without it — which is also why it has to be run somewhere that *does* have a
backend, or it never runs at all. CI does, in the `backend` job, and passes
`--dart-define=REQUIRE_BACKEND=true` so that a missing Worker there is a
failure rather than a quiet skip.

It is the only test that goes near the wire. The Vitest suite proves the
Durable Object against `workerd` and `sync_test.dart` proves the sync algorithm
against a fake, but neither can catch a generated client calling a path that
moved, a field that does not survive the JSON round trip, a refusal code mapped
to the wrong kind, or a payload key the server spells one way and the app reads
another. That last one is not hypothetical — it had already happened once, and
this is the test that would have caught it the same afternoon.

### The local database schema is versioned

The device holds the only copy of anything recorded offline and never pushed,
so a Drift migration that drops a table takes real money with it and there is
no server-side backup to restore from — by design. `drift_schemas/` holds a
snapshot of every shipped schema, and `test/data/migration_test.dart` fails the
moment the code drifts from the newest one.

After changing anything in `lib/data/local/tables.dart`, bump
`AppDatabase.schemaVersion`, add a step to `onUpgrade`, and then:

```bash
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

The domain layer is also run in a real browser:

```bash
flutter test --platform chrome test/domain
```

That is not redundant. On the web a Dart `int` is a JavaScript double and is
exact only to 2^53; a plausible expense multiplied by a 10^6-scaled weight
already exceeds that. The allocator uses `BigInt` for exactly this reason, and
this is the only run that proves it.

Browser storage and sync are tested separately against SQLite in OPFS, using
the same worker and WebAssembly assets shipped with the app:

```bash
cp web/sqlite3.wasm web/drift_worker.js test/browser/
flutter test --platform chrome --wasm --cross-origin-isolation test/browser
```

This covers first sync, groups created later, expense edits and deletions, and
reopening the database. Native SQLite tests alone cannot catch browser lock
failures. Repository mutations and sync pages each own one transaction; feed
and entry-writing helpers require that transaction instead of nesting one.

### Sync ownership and status

Repository mutations commit the local edit and outbox item together. The sync
engine owns each incoming page's transaction, including its cursor. Neither
path accesses Drift's internal transaction state.

One account-scoped coordinator handles foreground refreshes, group opens and
push wakes. The scheduler supplies launch, resume, connectivity and write
triggers. Requests received during a run coalesce into a follow-up so writes
that missed its push phase are not lost. The engine's database lease also
serializes background isolates and other tabs.

Failed discovery is an error, not an empty group list. Until the first full
refresh succeeds, an empty device shows progress or a retry notice. Cached
groups remain usable when a refresh fails. Pending uploads and permanent
refusals have separate notices.

Network and pull failures retry after 5 seconds with exponential backoff,
capped at 5 minutes. Upload deadlines live in the outbox and are restored on
the next launch; dependent writes cannot overtake a backed-off parent.
Permanent refusals require an explicit retry. Active-run status is kept in
memory and discarded on account changes, avoiding stale "running" flags after
a crash. Ledger rows, cursors and queued writes remain durable.

## Building

Local build success is not production approval.

Configuration is injected at build time, from a file rather than a dozen
`--dart-define` flags on one command line — which is how a release ends up
built against the wrong backend.

```bash
cp env/app.example.json env/app.json      # gitignored; fill it in
cp android/key.properties.example android/key.properties   # gitignored too

# Android
flutter build appbundle --release --dart-define-from-file=env/app.json

# Web, WasmGC with an automatic JS fallback for older browsers. This also
# injects Firebase's public web identifiers and versions the offline cache.
dart run tool/build_web.dart
```

`android/key.properties` points at the upload keystore and carries its
passwords, which makes it the one genuinely secret file in this project. Create
the key once, keep the `.jks` outside the repository, and do not lose it:

```bash
keytool -genkey -v -keystore ~/opensplit-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Without that file a release **APK** falls back to the debug key — fine for
putting on your own phone — and a release **bundle refuses to build**, because
that is the artefact Play would reject. The failure is a Gradle error naming
the file, rather than an upload rejected an hour later.

Check it before you build, because a wrong value here fails at runtime and
often silently:

```bash
dart run tool/verify_config.dart

# Or let google-services.json fill in the four values it is authoritative for
# — project id, project number, Android App ID and Android API key:
dart run tool/verify_config.dart ~/Downloads/google-services.json
```

Firebase issues a **different API key and a different App ID per platform** — a
browser key restricted to your domains, an Android key restricted to your
package name and signing certificate. Both live in `env/app.json` under
`WEB_`/`ANDROID_` names, and `lib/config.dart` picks the right pair with
`kIsWeb`, which is a compile-time constant. So there is no build command that
can be run with the wrong one, and the unused branch never reaches the bundle.

`web/sqlite3.wasm` and `web/drift_worker.js` are committed: Drift needs both at
runtime to use OPFS. OpenSplit deliberately has no IndexedDB fallback because a
second browser backend would be a second, independent local ledger.

OPFS also needs the page to be cross-origin isolated, which is why `/app/**` is
served with `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: credentialless`. That pair is what makes
`SharedArrayBuffer` available. If no safe OPFS implementation is available,
OpenSplit refuses to open the local ledger instead of silently changing its
storage backend.

The pair is also why **Google sign-in on the web is a redirect rather than a
button**. COOP `same-origin` severs the opener of every cross-origin popup, and
Google Identity Services answers into the window that opened it, so an in-page
Google button fails there — silently, and in release builds only, because the
assertion that would have caught it is compiled out. `Document-Isolation-Policy`
grants the same isolation while preserving popups, but only in Chromium, which
would have left Firefox and Safari without OPFS. So the client hands the whole
page to Google instead: a top-level navigation is unaffected by either header,
works identically on every browser, and needs no third-party cookies, no FedCM
and no JavaScript-origin allow-list. Android is unaffected and still signs in
natively, without leaving the app.

The source service workers intentionally contain unresolved placeholders. Only
`tool/build_web.dart` may produce a deployable web directory: it verifies the
configuration, injects Firebase's public identifiers, and keys the offline cache
to the commit being built. CI uses structurally valid inert identifiers to prove
the release build. After every CI gate passes, pushes to `main` build with real
production variables, deploy the Worker and the bundle together, and distribute
a signed AAB to Play closed testing. Release reruns the same CI checks before
publishing.
A manual **Release** run with **deploy unchecked** creates
artifacts only, for first-upload bootstrap.

Every integration is off unless configured, and hidden rather than shown broken:

| Key | Enables |
|---|---|
| `API_BASE_URL` | Sync and accounts |
| `GOOGLE_WEB_CLIENT_ID` | Sign in with Google |
| `FCM_PROJECT_ID`, `FCM_SENDER_ID`, and the `ANDROID_`/`WEB_` key and app id | Push |
| `FCM_VAPID_KEY` | Web push, in addition to the above |
| `LINK_HOST` | The host used in invite links |

### Exchange rates

Rates are fetched by the server, never by devices — so every member of a group
converts with the same numbers, and a modified client cannot put a rate in
front of anyone else. Everything is stored against a single base (USD), one row
per currency per day, so any pair is a division and there is no such thing as a
supported *pair*.

```bash
# Optional, and only for full coverage — see the table below.
cd server && npx wrangler secret put EXCHANGERATE_API_KEY
```

A daily cron (`0 4 * * *`, after ECB publishes) calls the `Fx` Durable Object,
which is the **only writer** of rates. It holds the history in its own SQLite
and publishes one blob per month to KV, where every device reads it through
`GET /api/fx`.

A singleton object rather than a scheduled function writing KV directly,
because KV is last-write-wins: the daily run and an on-demand backfill
rebuilding the same month from two reads would silently drop whichever rate
landed first, and the only symptom would be a month missing a currency.
Serializing writers is what the primitive is for. The object writes; the edge
serves, so a rate pull never crosses the planet to reach it.

Two providers run in order, the second filling what the first could not:

| Provider | Covers | History |
|---|---|---|
| Frankfurter (ECB) | ~30 currencies | yes, free |
| ExchangeRate-API | 166 currencies | no — free plan is latest only |

The ExchangeRate-API key is required for full coverage: without it only
Frankfurter runs, and AED, KWD, BHD, LKR, NPR and VND get no rate at all. An
unconfigured provider skips itself rather than failing the run, which is how a
fork runs on Frankfurter alone. The free tier is 1,500 requests a month and the
cron uses about 30.

**Fetch once, keep forever.** A rate is immutable once published, so nothing
already stored is ever overwritten — a second provider answering for a day we
already covered would otherwise make the `source` stamped on somebody's
converted expense quietly wrong.

**Backdated entries fetch on demand.** Recording an expense on a date the app
has never priced posts to `/api/fx/backfill`, which fetches that day and caches
it for everyone. The object refuses dates it can already answer, repeats within
the hour, futures, and dates chased more than five times — some days are
unanswerable, and without a ceiling every device retries them forever against
a quota. Six devices in one group sync the same backdated expense within a
second of each other, so this is the common case rather than the edge one.

The device reaches *backwards* for those. A high-water mark alone cannot
deliver a rate older than the ones already held, which is exactly what a
backfill produces — so the pull widens to the oldest expense it has no rate
for, once, and records how far back it went.

**Known limitation:** the ~136 currencies ECB does not publish have no free
historical source, so an entry backdated before the daily job started
accumulating gets no converted estimate for those. Balances are unaffected —
they are per-currency and exact.

Adding a provider is one adapter in `server/src/fx/providers.ts` plus one entry
in the array at the bottom of it. It used to be a row in an `fx_providers`
table that could be reordered without a deploy; that bought nothing, because
there was no interface to edit it with and every change was a migration
anyway. What was worth keeping is the health record — each provider's last
attempt, success and error — because "why is AED missing" is otherwise
unanswerable from outside.

### Firebase, for push and Google sign-in

One Firebase project supplies both, because creating it also creates the Google
Cloud project whose OAuth clients Google sign-in needs. **Turn Google Analytics
off** when creating it — see PRINCIPLES.md.

The app is configured entirely through the `env/*.json` files, so **no
`google-services.json` is needed at build time** and none should be committed —
you download it once, read two values out of it, and delete it. There is no
`com.google.gms.google-services` Gradle plugin in this project; `FirebaseOptions`
are passed explicitly in `lib/data/push/push_service.dart`. The console will
offer you the file anyway — skip it.

Register the Android app under package name `com.eigeninteractive.opensplit`,
and a separate web app for the web build. Then, in Project settings → General:

| Key in `env/app.json` | Where it comes from |
|---|---|
| `FCM_PROJECT_ID` | Project ID |
| `FCM_SENDER_ID` | Project number (digits only) |
| `WEB_FCM_API_KEY` | Your apps → the **web** app → SDK setup and configuration → Config → `apiKey` |
| `WEB_FCM_APP_ID` | the same snippet's `appId` (contains `:web:`) |
| `FCM_VAPID_KEY` | Cloud Messaging tab → Web Push certificates → Generate key pair |
| `ANDROID_FCM_API_KEY` | see below |
| `ANDROID_FCM_APP_ID` | see below |

The Android app offers no config snippet in the console — only a
`google-services.json` download. Download it and let the tool read it, rather
than copying four values by hand:

```bash
dart run tool/verify_config.dart ~/Downloads/google-services.json
```

That fills `FCM_PROJECT_ID`, `FCM_SENDER_ID`, `ANDROID_FCM_APP_ID` and
`ANDROID_FCM_API_KEY` from the one file that carries all four consistently, and
then checks the rest. The download is not needed at build time and must not be
committed — delete it afterwards.

**`FCM_PROJECT_ID` is the project *id*, not the display name.** The console
shows "OpenSplit" in large type and `opensplit-4a2b1` in small type; every API
wants the second. It is also the path segment in the console's own URL:
`console.firebase.google.com/project/<this>/overview`.

### Google sign-in

**Nothing here is created for you.** Firebase auto-creates OAuth clients only
when *Firebase Auth* is enabled, and this app authenticates through its own
Worker, so Firebase Auth is never switched on and Credentials stays empty.
Create both clients by hand, in the same Google Cloud project the Firebase
project made:

1. **Google Auth Platform → Branding** (formerly the OAuth consent screen).
   App name, support email, developer contact. Nothing works until this exists.
2. **Credentials → Create credentials → OAuth client ID → Web application.**
   Add `https://<your host>/api/auth/callback/google` as an authorized redirect
   URI, and your site origin under authorized JavaScript origins. Its
   **Client ID** is `GOOGLE_WEB_CLIENT_ID` — one value, used on both platforms,
   because the Worker verifies the ID token's audience against the web client
   even when the token was minted on Android. The same pair goes into the
   Worker as `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
3. **Credentials → Create credentials → OAuth client ID → Android.** Package
   name `com.eigeninteractive.opensplit`, plus the SHA-1 of the signing key.
   Its id is never needed in the app, but the client is what binds the package
   name and certificate. Create one for the upload key and for all three Play
   App Signing certificates: the original classical key and the new classical
   and post-quantum keys used by Android 17+. A missing client may surface as a
   `clientConfigurationError`, or even as `canceled`, in Credential Manager.
4. **The Worker's own secrets:** `wrangler secret put GOOGLE_CLIENT_ID` and
   `GOOGLE_CLIENT_SECRET`, the *web* client's pair. Locally they live in
   `server/.dev.vars`, which is gitignored; `server/.dev.vars.example` shows
   the shape.

```bash
# The debug SHA-1, for step 3 during development:
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android | grep SHA1
```

### Accounts: linking is not signing in

A session begins because somebody chose one of three things — Google, an email
code, or being a guest — and being a guest is a real account with no credential
attached, not a lesser mode. Attaching a credential to a guest session later has
to **link**: same account id, same rows, nothing to migrate. Signing in instead
mints or resumes a *different* account and leaves the guest holding every group
the person has created so far, at which point they are a stranger to their own
data.

That decision lives in `server/src/identity/routes.ts` rather than on the
device, and the move is the point: each of the three entry points tries the
linking call first and only falls back to signing in when the identity provably
belongs to somebody already — and then only when the caller has said the cost
has been explained. In TypeScript, inside the Worker, every one of those
branches is reachable from `vitest`, including the one that fires when an
identity is already claimed, which is exactly where the damage happens and
exactly what no Flutter test could reach before.

The app deliberately does *not* create a session on startup. It used to, and
that broke the arrival it was meant to protect: somebody who already had an
account and tapped an invite link had the single-use token spent by a throwaway
anonymous account, and no way into the group afterwards. `/join/:token` now
reads the link with `GET /api/links/{token}`, which is the one route that runs
with no session at all, shows what the link is for, and joins only after the
identity question has an answer.

### Two kinds of link

`/join/:token` serves both, so there is one URL shape, one App Links filter and
one route; which kind a token names is the server's business.

A **named invite** hands one unclaimed place to one person and is spent by
being used. It is the right link when you know who is coming: they
open it and become the "Priya" somebody already typed.

A **group link** lets anybody holding it join, until it expires after seven days
or is revoked. It is the link you paste into the chat you
already have, for a trip whose guest list does not exist yet. Possession is the
whole authorisation, which is a larger claim than an invite makes, so:

* there is one live link per group — a single row the group's Durable Object
  overwrites, which needs no unique index because the object is its only
  writer — and minting revokes whatever preceded it;
* it can be turned off without minting another;
* `link_created`, `link_revoked` and `member_joined` all land in the activity
  feed, so the group can see the door open, close, and be walked
  through. A group that can see who arrived has a better remedy than an
  approval queue, which is why there is not one.

Arriving on a group link asks which of the group's unclaimed placeholders you
are, if any. Claiming one is the same single-column update a named invite
performs — no expense is rewritten and no balance moves — and it is what stops
one shared link turning a group of six into a group of twelve.
`GET /api/links/{token}/placeholders` deliberately **requires** a session,
unlike the preview beside it: those are other people's names, which is more than
the token itself implies, and it is asked after an account has been chosen
rather than before.

Arriving as somebody new needs a name, and there is no sentinel. The name on the
account is used when there is one — anybody who signed in with Google or an
email address has one — and a guest who has never chosen one is asked on the
join screen. "Someone" in a ledger is worse than a question, and a sentinel
stored on a profile could never afterwards be told from a name somebody meant.

**Email codes, not magic links.** The app asks for an eight-digit code, because
a magic link opens in whichever browser the mail app prefers, loses the app's
context entirely, and is routinely consumed by corporate mail scanners before
the recipient ever sees it. The Worker sends it through Resend; set
`RESEND_API_KEY` as a secret. Without one, codes are logged rather than sent,
which is right for local development and would be a silent failure in
production — so the log line says so.

### One name, one ledger per account

Two structural rules that a lot of the code depends on:

**A person has one name.** It lives on `profiles`, and co-members can already
read each other's rows, so a rename travels with the next sync rather than
being copied into `members.display_name` once per group and drifting. The member
row's name and payment handle are placeholder storage, used only while nobody
has claimed the place; once somebody has, their account answers both.
`GroupLedger.nameOfMember` is the single point where that is resolved.

**The local database is named after the account** — `opensplit-<uid>`. Signing
in as somebody else opens somebody else's file, so one person's expenses cannot
appear under another's account whatever any calling code believes. Switching is
therefore non-destructive; signing out deletes that account's file, which is a
privacy decision about shared devices rather than a correctness one. The cost is
that reference data is per-account and re-pulled after a switch.

### Push notifications

The client values above cover the app. The fan-out also needs a service account.
Project settings → Service accounts → Generate new private key gives you the
JSON; unlike everything above, **it is a real secret**:

```bash
cd server
npx wrangler secret put FCM_PROJECT_ID
npx wrangler secret put FCM_SERVICE_ACCOUNT   # paste the whole JSON
```

There is no webhook, no shared secret and no trigger. The group's Durable
Object sends directly, inside `waitUntil`, after its own write has committed —
so the response goes back as soon as the expense is saved, and a person
recording one never waits on Google. A function reached over HTTP has to prove
who is calling it; a function the object calls in-process does not, which is
how three secrets became one and a `pg_net` dispatch became a method call.

With `FCM_PROJECT_ID` or `FCM_SERVICE_ACCOUNT` unset the send is skipped and
nothing else changes, which is why a deployment with no push configured still
records expenses normally.

**Three kinds wake a device:** an expense, somebody arriving, somebody leaving.
Not renames, archives or links — those belong in the activity feed, which is
read on purpose, rather than on a lock screen. `link_created` in particular
would wake a whole group to say that one of them tapped Share.

**The actor is excluded, not the author.** On an edit those are usually
different people, and the author is precisely who needs to hear that somebody
changed their expense.

**The OAuth token lives in KV**, not in a module variable. There is one isolate
in an Edge Function and potentially hundreds of group objects here, each in its
own place: a per-instance cache would mint a token per active group per hour,
which is hundreds of round trips to Google to say the same thing.

For web push, `dart run tool/build_web.dart` injects the public Firebase values
from the same configuration file as Flutter. Do not edit the worker by hand.
One worker owns `/app/` and handles both offline assets and push, so enabling
notifications cannot replace the offline worker.

**Permission is never requested at launch.** Android 13+ shows the system
dialog once or twice and then treats further asks as permanently denied, with
system settings as the only way back. The app asks in two places instead: the
Settings switch, and once after someone shares an invite — the first moment
being notified about a group means anything. Both show an in-app rationale
first, so the OS dialog is only ever spent on someone who has already agreed.

**Backgrounded is the case that matters, and it costs an isolate.** The message
is data-only, so nothing is drawn unless the app draws it — and a stub
background handler therefore means the only notifications anyone ever sees are
the ones that arrive while they are already looking at the app, which is the
one case a notification is not for. `lib/data/push/background_handler.dart`
runs in a background isolate with its own Firebase, its own HTTP client and a
second connection to the SQLite file (which is why the database is opened in
WAL mode with a busy timeout). It syncs, then formats with the same Dart the
screens use. It reloads the stored session for every message, honors the
notification preference, and cannot resume an account cleared by sign-out. It
never refreshes or rotates that session — the foreground owns it, and a second
writer could otherwise restore one after a sign-out — so background work with
an expired session waits for the next app resume. Push is best-effort, not a
delivery guarantee or the source of ledger correctness.

On the web there is no equivalent — a service worker cannot run Dart — so
`web/firebase-messaging-sw.js` deliberately draws nothing and web push only
wakes an open tab. Tapping any of these opens the entry it was about rather
than the app's front door, on all three paths: foreground, backgrounded, and
launched from cold.

## Developing against a local Worker with the real Firebase

The usual working setup: the API, the database and auth all local, but push
going through the real FCM project, because there is no local FCM.

```bash
dart run tool/build_web.dart --site-only
cd server && npm run db:migrate:local && npm run dev
```

`wrangler dev` runs the real Worker over local D1, KV and Durable Object
storage. Nothing it does touches a Cloudflare account and it needs no
credentials. It does need an assets directory to exist, which is what the first
line is for.

Config files are merged in order and **later files win**, so a local override
goes last:

```bash
cp env/local.example.json env/local.json

flutter run -d chrome \
  --dart-define-from-file=env/app.json \
  --dart-define-from-file=env/local.json
```

`env/local.json` only needs to override `API_BASE_URL`. Later files win, so it
goes last. `http://127.0.0.1:8787` is already the default in `lib/config.dart`,
so a bare `flutter run` against a local `wrangler dev` needs no defines at all —
just no Firebase.

There is no key to set alongside it. The backend is one origin serving the site,
the app bundle and the API, and a request carries a session or it carries
nothing, so there is no anonymous public identifier to configure.

**The URL depends on where the app runs**, and this is the step that wastes an
afternoon:

| Running on | `API_BASE_URL` |
|---|---|
| Chrome, on this machine | `http://127.0.0.1:8787` |
| Android emulator | `http://10.0.2.2:8787` — the emulator's own 127.0.0.1 is the emulator |
| Physical Android device | `http://<this machine's LAN address>:8787`, same Wi-Fi |

For the last two, start the Worker with `npx wrangler dev --ip 0.0.0.0`, which
it does not do by default.

Android has blocked cleartext HTTP since API 28, so a debug build also needs
`android/app/src/debug/res/xml/network_security_config.xml` — already committed,
and scoped to the debug source set so release builds keep HTTPS mandatory. Without
it every request fails with `CLEARTEXT communication not permitted`, and the
app shows a refresh failure while keeping saved data available.

### Push and rates, locally

One terminal. Both live inside the Worker now, so there is nothing separate to
serve and no trigger to point anywhere:

```bash
cd server && npm run dev
```

Put `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT` in `.dev.vars` if you want a
send to actually reach a device. Without them the object still runs its write,
skips the send, and logs nothing — which is the ordinary state for a fork and
not a failure.

The rate cron can be driven by hand, which is also what CI does before the
adapter tests:

```bash
npx wrangler dev --test-scheduled          # exposes the handler
curl 'http://127.0.0.1:8787/cdn-cgi/handler/scheduled?cron=0+4+*+*+*'
curl 'http://127.0.0.1:8787/api/fx?since=2026-01-01'
```

This reaches the real ECB feed, and with no `EXCHANGERATE_API_KEY` set the log
says which currencies went uncovered — `AED,VND,LKR,NPR,KWD,BHD`, which is
exactly the set ECB does not publish, and the whole reason there is a second
provider.

## Deploying

The deployed tree is two things, and the split is the point:

```
/            static HTML from site/   landing page, privacy, terms, delete-account
/app/        the Flutter client       every route go_router knows about
```

`site/` needs no engine, no session and no JavaScript, so a crawler, a Play
reviewer and a Google OAuth reviewer can all read what the app is. The client
used to sit at the root, which meant the public face of the product was a
sign-in screen — the router sends anyone without a session to `/welcome` — and
OAuth branding verification failed on exactly that.

Nothing in Dart knows about the prefix. `--base-href=/app/` puts it below the
path URL strategy, so go_router still sees `/g/123` while the browser shows
`/app/g/123`. Two places do encode it, and `test/deep_link_host_test.dart`
holds them together: the invite URL in `lib/domain/repositories/invite_api.dart`
and the App Links `pathPrefix` in `AndroidManifest.xml`.

Both halves are served by the Worker, from the same origin as the API. There is
no separate hosting product and no CORS, which is what lets the web build keep
its session in a first-party `HttpOnly` cookie rather than a token JavaScript
can read.

```bash
dart run tool/build_web.dart          # builds /app/, then copies site/ over the root
cd server && npx wrangler deploy      # script and bundle, one version
```

`build/web` is the Worker's `assets.directory`, so those two commands are one
deploy: the script and the front end go up together and become live together,
and a client that is newer or older than the API it talks to is a state this
arrangement cannot reach. `docs/cloudflare-runbook.md` has the account-level
steps that have to happen once before the second command works at all.

Three parts of serving are configuration rather than code, and they live beside
the pages they describe:

- `site/_headers` — security headers for everything, and cross-origin isolation
  for `/app/*` only. Cloudflare parses it and never serves it. It is a third the
  length of the Firebase config it replaced, because most of that file was
  spelling out per path what Workers already does to every asset: revalidate
  always, with an ETag.
- `site/_redirects` — the client routes that used to live at the host root,
  permanently redirected under `/app`. Those URLs are in other people's chat
  histories.
- `server/src/app.ts` — the deep-link fallback, by hand. `/app/join/<token>` has
  to return the client's document rather than a 404, since that is the entire
  point of an invite link, and none of the platform's three `not_found_handling`
  settings answers the right document: two of them would hand a deep link the
  landing page or the 404 page instead.

For work on the server alone, `dart run tool/build_web.dart --site-only` builds
the static root in about a second and skips the Flutter client. `wrangler dev`
refuses to start without an assets directory, and a two-minute Flutter build is
a strange price for editing a route handler.

`opensplit.eigeninteractive.com` is the official domain, and the only one. It
hosts the web app, it is the host written into every invite link (`LINK_HOST` in
`lib/config.dart`), and it is the single entry in the App Links intent filter.
`workers.dev` is switched off so that there is no second address at all.

That is a deliberate commitment rather than a default. Every host the app has
ever claimed has to keep serving, keep resolving, and keep an
`assetlinks.json` matching the app's signing key — for as long as any link
naming it exists, which for a link pasted into a chat is indefinitely. A second
host doubles that obligation and buys nothing, since both would serve the same
build.

A vanity domain may point here later. If one does it should **redirect** to
`opensplit.eigeninteractive.com` rather than serve alongside it. A redirect
leaves one URL that links are minted with and one origin that owns the stored
data — which matters here, because this is a local-first app whose database is
keyed to its origin, so a second origin is a second, empty copy of the app.

After the first deploy, confirm the file actually shipped, because the failure
mode is silence:

```bash
curl -sI https://opensplit.eigeninteractive.com/.well-known/assetlinks.json
```

It must return `200` and `content-type: application/json`. HTML means the
deep-link fallback swallowed it, and App Links will not verify.

**Before the first Play Store release**, read
[`site/.well-known/README.md`](site/.well-known/README.md). `assetlinks.json`
lists all three Google Play App Signing certificates: the original classical
key for Android 16 and below, plus the new classical and post-quantum keys used
by Android 17+. Play re-signs each upload with the keys appropriate for the
installing device, so every one must be authorized.

It should also list the **upload key**, so that release APKs installed directly
verify too. All four certificates are shown under *Play Console → Test and
release → Setup → App signing*. Getting this wrong is silent in the worst way:
links simply open in a browser, with nothing in the app to say why.

Anonymous sign-in is unauthenticated row creation, so it is swept rather than
gated: a weekly job deletes guest accounts that joined no group and were never
used again after ninety days. No CAPTCHA — it would sit in front of the one
flow that has to be invisible, and an invite link that opens a puzzle is an
invite link nobody follows.

Code generation runs over Drift tables, Freezed models and Riverpod providers.
After changing any of them, re-run `dart run build_runner build`.

### Layout

```
lib/domain/         pure Dart: splitting, balance fold, simplify. No Flutter,
                    no imports from data/.
lib/data/           Drift database, repositories, sync. The only place the
                    backend is referenced.
lib/application/    Riverpod providers and view models.
lib/presentation/   screens and widgets.
server/src/do/      the Durable Objects: one class per group, and the
                    singleton that writes exchange rates.
server/src/api/     the HTTP layer, declared with @hono/zod-openapi so the
                    committed contract cannot drift from the routes.
server/migrations/  D1. Generated by drizzle-kit, applied by wrangler.
                    The Durable Objects have their own two sets, bundled
                    into the script because each object migrates itself.
site/               the static root: landing page, the three document
                    pages, and the _headers and _redirects that configure
                    serving.
drift_schemas/      a snapshot of every shipped local schema, so a future
                    migration can be tested against a real old database
                    rather than a guess at one.
docs/               procedures and rules that are too long for a commit
                    message and have to be followed exactly: standing the
                    backend up, rebuilding it, and what to know before
                    changing the local database.
```

Migrations are never edited in place, on either side. `drizzle-kit generate`
appends, `wrangler d1 migrations apply` runs what is new, and each group object
applies its own outstanding ones on first open after a deploy — so a file that
has already run somewhere has run for good. Correcting one that shipped means
rebuilding rather than editing; see
[docs/resetting-the-backend.md](docs/resetting-the-backend.md), which is mostly
about how much harder that is for a Durable Object than for a database.

The domain layer is pure functions over immutable data, which is why it is
tested with generated cases rather than examples: thousands of random entry
sets asserting that balances sum to exactly zero, that every entry balances,
that rounding is identical regardless of member order, and that applying the
suggested settlements leaves nothing owed.

## Licence

Copyright © 2026 EigenInteractive.

[AGPL-3.0](LICENSE). If you run a modified OpenSplit as a service, your users
are entitled to your changes. The app carries that obligation rather than
leaving it to this file: *Settings → About* links to the source, and
`REPOSITORY_URL` is a build-time define so that a fork's copy points at the
fork.

The typefaces are not ours and are not under that licence. Instrument Sans and
JetBrains Mono are bundled under the SIL Open Font License 1.1, with the notices
and the licence text in [assets/google_fonts/LICENSE](assets/google_fonts/LICENSE)
— which the app also shows, under *About → Open-source licences*.

### The name and the mark

AGPL-3.0 covers the code. The name *OpenSplit* and the brand assets in
`assets/brand/`, `assets/icon/` and `brand/` stay with EigenInteractive, so a
fork will want its own name and its own mark. That is the usual arrangement —
GPLv3 §7(e), which AGPL-3.0 incorporates, exists so that a copyright licence
need not hand over a trademark — and the code, which is the part worth taking,
is yours to take.

## Issues

Bug reports and feature requests are very welcome. The templates ask for the
few things that make a report actionable — mostly the exact amounts, since
rounding bugs hide in the last paisa.
