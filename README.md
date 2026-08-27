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
- **Self-hostable for real.** The server stores rows and enforces one
  invariant. It computes nothing. The same local stack and migrations used by
  CI are the supported self-host path; see [docs/SELF_HOSTING.md](docs/SELF_HOSTING.md).

## Architecture in one paragraph

A Flutter client (Riverpod, Drift, go_router) holds the entire journal in
SQLite and does all computation locally — split arithmetic, the balance fold,
debt simplification, analytics. Supabase is a paginated row feed behind a Dart
repository interface: Postgres with row-level security and a deferred
constraint trigger that enforces `sum(payers) = sum(shares) = amount` at commit.
Reads outnumber writes roughly 50:1, so putting reads on devices people already
own is what makes "free forever" credible rather than aspirational.

## Development

Requires the Flutter SDK, Docker, and the Supabase CLI.

```bash
flutter pub get
dart run build_runner build        # Drift, Freezed and Riverpod codegen
flutter test                       # domain, storage, sync and UI flow tests
flutter run
```

The local backend:

```bash
supabase start                     # applies supabase/migrations in order
supabase db reset                  # rebuild from scratch
supabase test db                   # pgTAP: invariants, RLS, invite claims
```

The database tests are not optional decoration. They cover the deferred
constraint trigger rejecting unbalanced entries, that `is_group_member` does
not recurse through its own policy (Postgres 42P17, the standard failure for
this shape of schema), that entries cannot be hard-deleted, that an anonymous
account cannot destroy a group, and that an invite token can be spent exactly
once by someone with no other access to the group.

They also cover what one member of a group can do to another, which is a
different question from what a stranger can do and has a much less obvious
answer. An RLS policy chooses rows; it cannot say "this column, but only on
your own row", and its `WITH CHECK` cannot see the old row at all. So the
column rules live in `guard_member_update` instead, and the tests are what say
that an ordinary member cannot promote themselves to owner, cannot blank
somebody's `profile_id` and evict them, and — the one that moves real money —
cannot rewrite another member's UPI handle so a settle-up handoff pays the
wrong person.

```bash
flutter test test/data/supabase_integration_test.dart   # needs supabase start
```

That runs the real adapter against the local instance. It skips itself when
nothing is listening, so `flutter test` stays green without it — which is also
why it has to be run somewhere that *does* have a backend, or it never runs at
all. CI does, in the `database` job. It is the only thing that catches a wrong
RPC signature, a PostgREST filter that does not mean what it looks like, or an
RLS policy that forbids something the app has to do. Every one of those has
already happened once.

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

## Building

See [release readiness and remaining gates](docs/RELEASE_READINESS.md) before
publishing. Local build success is not production approval.

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
runtime to use OPFS, and a build without them falls back to a database that does
not survive a reload.

The source service workers intentionally contain unresolved placeholders. Only
`tool/build_web.dart` may produce a deployable web directory: it verifies the
configuration, injects Firebase's public identifiers, and keys the offline cache
to the commit being built. CI uses structurally valid inert identifiers to prove
the release build; the manual **Release candidate** workflow requires the real
production variables and Android upload-key secrets, reruns every gate, and
uploads artifacts without deploying either one.

Every integration is off unless configured, and hidden rather than shown broken:

| Key | Enables |
|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Sync and accounts |
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

```
supabase functions deploy fetch-fx
supabase secrets set FX_FETCH_SECRET="$(openssl rand -hex 32)" \
                     EXCHANGERATE_API_KEY=<your key>

# Point the scheduled job at the function:
insert into app_settings (key, value) values
  ('fx_function_url', 'https://<project>.supabase.co/functions/v1/fetch-fx'),
  ('fx_fetch_secret', '<the same FX_FETCH_SECRET>');

# Seed history so backdated entries can be converted from day one:
select trigger_fx_fetch('{"backfill_days": 120}'::jsonb);
```

A daily `pg_cron` job (16:30 UTC, after ECB publishes) keeps today topped up.
Two providers run in `priority` order, the second filling what the first could
not:

| Provider | Covers | History |
|---|---|---|
| Frankfurter (ECB) | ~30 currencies | yes, free |
| ExchangeRate-API | 166 currencies | no — free plan is latest only |

The ExchangeRate-API key is required for full coverage: without it only
Frankfurter runs, and AED, KWD, BHD, LKR, NPR and VND get no rate at all.
The free tier is 1,500 requests a month and the cron uses about 30.

**Fetch once, keep forever.** A rate is immutable once published, so every
fetched row is stored permanently and synced to every device — not scoped to
whichever group happened to need it. Clients keep a high-water mark and only
ask for what came after it.

**Backdated entries fetch on demand.** Recording an expense on a date the app
has never priced calls `request_fx_backfill(date, currency)`, which fetches
that day and caches it for everyone. The server refuses dates it can already
answer, repeats within a day, futures, anything over five years old, and more
than twenty requests an hour.

**Known limitation:** the ~136 currencies ECB does not publish have no free
historical source, so an entry backdated before the daily job started
accumulating gets no converted estimate for those. Balances are unaffected —
they are per-currency and exact.

Adding a provider is one adapter in `supabase/functions/fetch-fx/providers/`
plus one row in `fx_providers`; reordering or disabling one is just the row.

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
when *Firebase Auth* is enabled, and this app authenticates through Supabase, so
Firebase Auth is never switched on and Credentials stays empty. Create both
clients by hand, in the same Google Cloud project the Firebase project made:

1. **Google Auth Platform → Branding** (formerly the OAuth consent screen).
   App name, support email, developer contact. Nothing works until this exists.
2. **Credentials → Create credentials → OAuth client ID → Web application.**
   Add `https://<project-ref>.supabase.co/auth/v1/callback` as an authorized
   redirect URI, and your site origins under authorized JavaScript origins.
   Its **Client ID** is `GOOGLE_WEB_CLIENT_ID` — one value, used on both
   platforms, because Supabase verifies the ID token's audience against the web
   client even when the token was minted on Android.
3. **Credentials → Create credentials → OAuth client ID → Android.** Package
   name `com.eigeninteractive.opensplit`, plus the SHA-1 of the signing key.
   Its id is never needed in the app, but **without this client Android sign-in
   fails with `ApiException: 10`** — the client is what binds the package name
   and certificate. Add both the upload key and Play App Signing's SHA-1, the
   same dual-key problem as `assetlinks.json`.
4. **Supabase dashboard → Authentication → Providers → Google:** enable it, and
   paste the *web* client's ID and secret.

```bash
# The debug SHA-1, for step 3 during development:
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android | grep SHA1
```

### Accounts: two settings that are not optional

A session begins because somebody chose one of three things — Google, an email
code, or being a guest — and being a guest is a real account with no credential
attached, not a lesser mode. Attaching a credential to a guest session later has
to **link**: same user id, same rows, nothing to migrate. Two things on the
Supabase side have to be right or that silently becomes something else entirely.

The app deliberately does *not* create a session on startup. It used to, and
that broke the arrival it was meant to protect: somebody who already had an
account and tapped an invite link had the single-use token spent by a throwaway
anonymous account, and no way into the group afterwards. `/join/:token` now
reads the invite with `peek_invite` — the one function granted to `anon` —
shows what the link is for, and redeems only after the identity question has an
answer.

**1. Allow manual linking.** *Authentication → Providers → Allow manual
linking*, and `enable_manual_linking = true` in `supabase/config.toml` for
local. Attaching Google goes through `linkIdentityWithIdToken`, which is
refused outright when this is off. Its cousin `signInWithIdToken` does not
link: it signs in as a *different* user and leaves the anonymous one holding
every group the person had created, at which point the new account is a
stranger to its own data and every push is refused by RLS. The app refuses to
fall back to it silently, and says which switch is off instead — but the switch
still has to be on.

**2. Email templates.** The app asks for a six-digit code. Supabase's stock
templates send a magic link and no token at all, so against them the "check
your email" step waits for a number that is never sent. `supabase/templates/`
holds three that carry `{{ .Token }}`; local picks them up from `config.toml`,
and a hosted project needs them pasted into *Authentication → Emails →
Templates* by hand, because templates are **not** deployed by `supabase db
push`. See [`supabase/templates/README.md`](supabase/templates/README.md).

Also leave `enable_confirmations = true`. With it off an email change is
applied outright, so a guest session can claim any address at all, having proved
nothing — and the real owner of that address finds it already spoken for.

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

The client values above cover the app. The fan-out also needs a service account,
three function secrets and a webhook. Project settings → Service accounts →
Generate new private key gives you the JSON; unlike everything above, **it is a
real secret**:

```
supabase functions deploy notify-entry
supabase secrets set FCM_PROJECT_ID=your-project \
                     FCM_SERVICE_ACCOUNT="$(cat service-account.json)" \
                     NOTIFY_WEBHOOK_SECRET="$(openssl rand -hex 32)"

# Point the trigger at the function, exactly as the rate fetch is pointed:
insert into app_settings (key, value) values
  ('notify_function_url',
   'https://<project>.supabase.co/functions/v1/notify-entry'),
  ('notify_webhook_secret', '<the same NOTIFY_WEBHOOK_SECRET>');
```

There is deliberately **no Database Webhook to create in the dashboard**. A
Supabase webhook is a row that creates a trigger calling
`supabase_functions.http_request()`; `trg_entries_notify` is that trigger,
declared in `20260101000008_push.sql` and applied by `db push` like everything
else. So it cannot be lost, the secret lives beside `fx_fetch_secret` rather
than in dashboard config, and the chain works on any Postgres with pg_net.

Until both rows are set the trigger no-ops, which is why a deployment with no
push configured still records expenses normally.

**The secret is not optional.** The function refuses to run without it, because
otherwise anyone holding the publishable key — which is public by design —
could drive the fan-out.

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
runs in a background isolate with its own Firebase, its own Supabase client and
a second connection to the SQLite file (which is why the database is opened in
WAL mode with a busy timeout). It syncs, then formats with the same Dart the
screens use. It reloads the stored session for every message, honors the
notification preference, and cannot resume an account cleared by sign-out.
Token refresh and persistence belong only to the foreground SDK; background
work with an expired session waits for the next app resume. Push is best-effort,
not a delivery guarantee or the source of ledger correctness.

On the web there is no equivalent — a service worker cannot run Dart — so
`web/firebase-messaging-sw.js` deliberately draws nothing and web push only
wakes an open tab. Tapping any of these opens the entry it was about rather
than the app's front door, on all three paths: foreground, backgrounded, and
launched from cold.

## Developing against local Supabase with the real Firebase

The usual working setup: Postgres, edge functions and auth all local, but push
going through the real FCM project, because there is no local FCM.

Config files are merged in order and **later files win**, so a local override
goes last:

```bash
cp env/local.example.json env/local.json

flutter run -d chrome \
  --dart-define-from-file=env/app.json \
  --dart-define-from-file=env/local.json
```

`env/local.json` only needs to override `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. Later files win, so it goes last. The local publishable key is the same for everyone
and is already the default in `lib/config.dart`, so a bare `flutter run` with no
defines at all is already a local-Supabase build — just without Firebase.

**The URL depends on where the app runs**, and this is the step that wastes an
afternoon:

| Running on | `SUPABASE_URL` |
|---|---|
| Chrome, on this machine | `http://127.0.0.1:54321` |
| Android emulator | `http://10.0.2.2:54321` — the emulator's own 127.0.0.1 is the emulator |
| Physical Android device | `http://<this machine's LAN address>:54321`, same Wi-Fi |

Android has blocked cleartext HTTP since API 28, so a debug build also needs
`android/app/src/debug/res/xml/network_security_config.xml` — already committed,
and scoped to the debug source set so release builds keep HTTPS mandatory. Without
it every request fails with `CLEARTEXT communication not permitted`, which in
this app looks like a sync that never completes, because sync failures are
swallowed by design.

### Push, locally

Three terminals:

```bash
supabase start                                    # database, auth, storage
supabase functions serve --env-file supabase/functions/.env
./supabase/dev/local-notify.sh                    # points the trigger locally
```

`supabase/functions/.env` needs `NOTIFY_WEBHOOK_SECRET` (any random string
locally), plus `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT` if you want the send
to actually reach a device. Without the FCM pair the function still runs and
answers `unconfigured`, which is enough to prove the wiring.

The trigger comes from the migrations and is always present. What that script
writes is the two `app_settings` rows it reads, pointing at the functions
running on the host. **`supabase db reset` clears them** — rerun the script
afterwards, or the trigger keeps firing into a URL it does not have and pushes
silently stop.

To check the chain without a device:

```bash
curl -s -X POST http://127.0.0.1:54321/functions/v1/notify-entry \
  -H 'Content-Type: application/json' \
  -H "x-webhook-secret: $(grep '^NOTIFY_WEBHOOK_SECRET=' supabase/functions/.env | cut -d= -f2-)" \
  -d '{"type":"UPDATE","table":"groups","record":null}'
# -> ignored

# And after adding an expense in the app, what the database got back:
docker exec supabase_db_opensplit psql -U postgres \
  -c "select status_code, content from net._http_response order by id desc limit 3;"
# -> 200 | nobody to wake      (no devices registered yet)
# -> 200 | ok                  (a device was notified)
```

A wrong secret returns `403`, which is the function refusing to be driven by
anyone holding the publishable key.

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

Any host works, provided it serves an SPA fallback under `/app` —
`/app/join/<token>` must return the app shell rather than a 404, since that is
the entire point of an invite link — and serves `site/` as real files at the
root. `firebase.json` does both.

```bash
firebase use --add                 # writes .firebaserc, which is gitignored
dart run tool/build_web.dart       # builds /app/, then copies site/ over the root
firebase deploy --only hosting
```

`opensplit.web.app` is the official domain, and the only one. It hosts the web
app, it is the host written into every invite link (`LINK_HOST` in
`lib/config.dart`), and it is the single entry in the App Links intent filter.

That is a deliberate commitment rather than a default. Every host the app has
ever claimed has to keep serving, keep resolving, and keep an
`assetlinks.json` matching the app's signing key — for as long as any link
naming it exists, which for a link pasted into a chat is indefinitely. A second
host doubles that obligation and buys nothing, since both would serve the same
build.

A vanity domain may point here later. If one does it should **redirect** to
`opensplit.web.app` rather than serve alongside it. A redirect leaves one URL
that links are minted with and one origin that owns the stored data — which
matters here, because this is a local-first app whose database is keyed to its
origin, so a second origin is a second, empty copy of the app.

After the first deploy, confirm the file actually shipped, because the failure
mode is silence:

```bash
curl -sI https://opensplit.web.app/.well-known/assetlinks.json
```

It must return `200` and `content-type: application/json`. HTML means the SPA
rewrite swallowed it, and App Links will not verify.

**Before the first Play Store release**, read
[`site/.well-known/README.md`](site/.well-known/README.md). `assetlinks.json`
now lists the Google Play App Signing key, which is the certificate every
install from the Store actually carries — Play re-signs each upload with it, so
it and not the upload key is what Android checks.

It should also list the **upload key**, so that release APKs installed directly
verify too. Both fingerprints are shown together under *Play Console → Test and
release → Setup → App signing*. Getting this wrong is silent in the worst way:
links simply open in a browser, with nothing in the app to say why.

Anonymous sign-in is unauthenticated row creation, so it is rate limited rather
than gated: `anonymous_users = 30` per hour per IP in `supabase/config.toml`,
plus a nightly job that deletes anonymous accounts which never joined a group.
No CAPTCHA — it would sit in front of the one flow that has to be invisible,
and an invite link that opens a puzzle is an invite link nobody follows.

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
supabase/           migrations, organised by subject rather than by date:
                    foundation, currencies, identity, groups, entries, fx,
                    invites, push, write path, security, grants, jobs.
                    Plus templates/, the email templates that carry the code
                    the app asks for.
drift_schemas/      a snapshot of every shipped local schema, so a future
                    migration can be tested against a real old database
                    rather than a guess at one.
docs/               the product requirements document.
```

The migrations are edited in place rather than appended to while the app is
unreleased — that is what keeps them readable by subject — so applying a change
locally means `supabase db reset`, not `supabase db push`. Once there is a
deployment holding real data that stops being true, and the file numbering
starts going up.

The domain layer is pure functions over immutable data, which is why it is
tested with generated cases rather than examples: thousands of random entry
sets asserting that balances sum to exactly zero, that every entry balances,
that rounding is identical regardless of member order, and that applying the
suggested settlements leaves nothing owed.

## Licence

[AGPL-3.0](LICENSE). If you run a modified OpenSplit as a service, your users
are entitled to your changes.
