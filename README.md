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
  invariant. It computes nothing.

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

`test/data/supabase_integration_test.dart` runs the real adapter against that
local instance. It skips itself when nothing is listening, so `flutter test`
stays green without it — but it is the only thing that catches a wrong RPC
signature, a PostgREST filter that does not mean what it looks like, or an RLS
policy that forbids something the app has to do. Every one of those has already
happened once.

The domain layer is also run in a real browser:

```bash
flutter test --platform chrome test/domain
```

That is not redundant. On the web a Dart `int` is a JavaScript double and is
exact only to 2^53; a plausible expense multiplied by a 10^6-scaled weight
already exceeds that. The allocator uses `BigInt` for exactly this reason, and
this is the only run that proves it.

## Building

Configuration is injected at build time, from files rather than a dozen
`--dart-define` flags on one command line — which is how a release ends up
built against the wrong backend.

There are three, because **Firebase issues a different API key and a different
App ID per platform**. One combined file would have to be edited between an
Android build and a web build, which is the same footgun in a smaller box.

```bash
for f in common android web; do cp env/$f.example.json env/$f.json; done

# Android
flutter build appbundle --release \
  --dart-define-from-file=env/common.json \
  --dart-define-from-file=env/android.json

# Web, WasmGC with an automatic JS fallback for older browsers.
flutter build web --wasm --release \
  --dart-define-from-file=env/common.json \
  --dart-define-from-file=env/web.json
```

The real files are gitignored; the `.example.json` ones are the templates.
Later files win, so the platform file supplies what `common.json` leaves out.

`web/sqlite3.wasm` and `web/drift_worker.js` are committed: Drift needs both at
runtime to use OPFS, and a build without them falls back to a database that does
not survive a reload.

Every integration is off unless configured, and hidden rather than shown broken:

| Key | Enables |
|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Sync and accounts |
| `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID` | Sign in with Google |
| `FCM_API_KEY`, `FCM_APP_ID`, `FCM_SENDER_ID`, `FCM_PROJECT_ID` | Push |
| `FCM_VAPID_KEY` | Web push (in addition to the four above) |
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

**`env/common.json`** — the same for both platforms:

| Value | Where it comes from |
|---|---|
| `FCM_PROJECT_ID` | Project ID |
| `FCM_SENDER_ID` | Project number (digits only) |

**`env/web.json`** — Your apps → the **web** app → SDK setup and configuration
→ Config. That prints a `firebaseConfig` object:

| Value | Field |
|---|---|
| `FCM_API_KEY` | `apiKey` |
| `FCM_APP_ID` | `appId` (contains `:web:`) |
| `FCM_VAPID_KEY` | Cloud Messaging tab → Web Push certificates → Generate key pair |

**`env/android.json`** — Your apps → the **Android** app offers no config
snippet, only a `google-services.json` download. Download it, read two fields
out, and delete it — it is not used at build time and must not be committed:

```bash
jq -r '.client[0].api_key[0].current_key,
       .client[0].client_info.mobilesdk_app_id' google-services.json
```

The first line is `FCM_API_KEY`, the second `FCM_APP_ID` (it contains
`:android:`).

**Do not reuse one key for both.** Firebase creates a browser key restricted to
your domains and an Android key restricted to your package name and signing
certificate. Swapping them often works on the day and breaks the moment either
restriction is tightened, with no error that says so.

For Google sign-in, from the Google Cloud console → APIs & Services →
Credentials on the *same* project:

- The **Web** OAuth client id is both `GOOGLE_WEB_CLIENT_ID` and
  `GOOGLE_SERVER_CLIENT_ID`. That is not a typo: Supabase verifies the ID token's
  audience against the web client even when the token was minted on Android.
- The **Android** OAuth client needs the SHA-1 of the signing key. Add both the
  upload key and Play App Signing's, the same way `assetlinks.json` needs both.
- In the Supabase dashboard → Authentication → Providers → Google: enable it,
  set the client id and secret from the web client, and add the Android client
  id under Authorized Client IDs.

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
```

Then add a database webhook on `entries` (INSERT only) pointing at the
function, with a header `x-webhook-secret` set to the same value.

**The secret is not optional.** The function refuses to run without it, because
otherwise anyone holding the publishable key — which is public by design —
could drive the fan-out.

For web push, copy the same four values from `env/web.json` and
`env/common.json` into `web/firebase-messaging-sw.js`. That file is loaded by
the browser before any Dart runs, so it cannot read a define file; the
duplication is unavoidable.

**Permission is never requested at launch.** Android 13+ shows the system
dialog once or twice and then treats further asks as permanently denied, with
system settings as the only way back. The app asks in two places instead: the
Settings switch, and once after someone shares an invite — the first moment
being notified about a group means anything. Both show an in-app rationale
first, so the OS dialog is only ever spent on someone who has already agreed.

## Developing against local Supabase with the real Firebase

The usual working setup: Postgres, edge functions and auth all local, but push
going through the real FCM project, because there is no local FCM.

Config files are merged in order and **later files win**, so a local override
goes last:

```bash
cp env/local.example.json env/local.json

flutter run -d chrome \
  --dart-define-from-file=env/common.json \
  --dart-define-from-file=env/web.json \
  --dart-define-from-file=env/local.json
```

`env/local.json` only needs to override `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. The local publishable key is the same for everyone
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
./supabase/dev/local-webhook.sh                   # the entries INSERT trigger
```

`supabase/functions/.env` needs `NOTIFY_WEBHOOK_SECRET` (any random string
locally), plus `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT` if you want the send
to actually reach a device. Without the FCM pair the function still runs and
answers `unconfigured`, which is enough to prove the wiring.

There is no dashboard locally, so the webhook is a trigger created by that
script. **`supabase db reset` drops it** — rerun the script afterwards, or push
stops firing with nothing to say why.

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

The web build is static. Any host works, provided it serves an SPA fallback —
`/join/<token>` must return the app shell rather than a 404, since that is the
entire point of an invite link.

`firebase.json` configures Firebase Hosting; `web/_redirects` does the same job
on Cloudflare Pages and Netlify.

```bash
firebase use --add                 # writes .firebaserc, which is gitignored
flutter build web --wasm --release \
  --dart-define-from-file=env/common.json \
  --dart-define-from-file=env/web.json
firebase deploy --only hosting
```

The app claims two hosts — `opensplit.eigeninteractive.com` and Firebase
Hosting's own `opensplit.web.app` — so both appear in the App Links intent
filter and both must serve `/.well-known/assetlinks.json`. Pointing both at one
Hosting site means one deploy covers both. Invite links are *generated* with
`LINK_HOST` only, which is why that is a single canonical value: a link pasted
into a chat outlives whichever domain was current when it was made.

After the first deploy, confirm the file actually shipped, because the failure
mode is silence:

```bash
curl -sI https://opensplit.eigeninteractive.com/.well-known/assetlinks.json
curl -sI https://opensplit.web.app/.well-known/assetlinks.json
```

Both must return `200` and `content-type: application/json`. HTML means the SPA
rewrite swallowed it, and App Links will not verify.

**Before the first Play Store release**, read
[`web/.well-known/README.md`](web/.well-known/README.md). `assetlinks.json`
currently lists only a local debug key. App Links will verify perfectly on your
machine and fail for every real user until it also lists the upload key *and*
the Google Play App Signing key — and the failure is silent: links just open in
a browser.

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
docs/               the product requirements document.
```

The domain layer is pure functions over immutable data, which is why it is
tested with generated cases rather than examples: thousands of random entry
sets asserting that balances sum to exactly zero, that every entry balances,
that rounding is identical regardless of member order, and that applying the
suggested settlements leaves nothing owed.

## Licence

[AGPL-3.0](LICENSE). If you run a modified OpenSplit as a service, your users
are entitled to your changes.
