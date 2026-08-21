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

```bash
# Web, WasmGC with an automatic JS fallback for older browsers.
flutter build web --wasm --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...

# Android
flutter build appbundle --release
```

`web/sqlite3.wasm` and `web/drift_worker.js` are committed: Drift needs both at
runtime to use OPFS, and a build without them falls back to a database that does
not survive a reload.

Every integration is off unless configured, and hidden rather than shown broken:

| `--dart-define` | Enables |
|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Sync and accounts |
| `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID` | Sign in with Google |
| `FCM_API_KEY`, `FCM_APP_ID`, `FCM_SENDER_ID`, `FCM_PROJECT_ID` | Push |
| `LINK_HOST` | The host used in invite links |

## Deploying

The web build is static. Any host works, provided it serves an SPA fallback —
`/join/<token>` must return the app shell rather than a 404, since that is the
entire point of an invite link. `web/_redirects` covers Cloudflare Pages and
Netlify.

**Before the first Play Store release**, read
[`web/.well-known/README.md`](web/.well-known/README.md). `assetlinks.json`
currently lists only a local debug key. App Links will verify perfectly on your
machine and fail for every real user until it also lists the upload key *and*
the Google Play App Signing key — and the failure is silent: links just open in
a browser.

Turnstile must be attached to the anonymous sign-in endpoint before the backend
is public. Anonymous sign-in is unauthenticated row creation; without a CAPTCHA
in front of it, anyone can mint users and rows indefinitely.

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
supabase/           migrations, in order. 0001 is the locked initial schema.
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
