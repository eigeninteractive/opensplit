# Release readiness — 27 August 2026

Status: substantial implementation hardening is complete, but this is not a
production-release approval. Nothing has been deployed or published. Local
verification does not establish that hosted credentials, signing, or device
integrations work.

## Preserved user changes

- Static landing and legal pages live in `site/` at the host root.
- Flutter lives under `/app/`; only that subtree receives the SPA rewrite.
- Restored sessions are synchronous, preserving the no-sign-in-flash reload.
- Existing staged asset moves and unrelated edits remain intact.

## Implemented

| Area | Changes |
| --- | --- |
| Database security | Removed direct entry/payer/share mutation access; explicit grants; restricted helper execution; owner-scoped token unregister; authenticated FX backfill. |
| Conflict safety | Versioned delete RPC; stale edits/deletes are retained for resolution; open editors cannot overwrite a newer local version. |
| Local durability | Entry, group, member, and profile mutations commit with their outbox writes. Queue failures roll back data and provisional history. |
| Concurrent sync | Revision-token acknowledgements preserve edits made during upload. Pulls protect dirty rows independently of device clocks. SQLite leases serialize engines across tabs/isolates. |
| Session isolation | Persisted session generations fence late responses after cleanup. Sign-out checks unsynced writes atomically and late editor writes fail closed. Auth-stream changes remain reactive without an initial loading frame. |
| Network failure | Bounded waits retain timed-out writes. A connection failure stops the batch instead of paying a timeout for every queued row. |
| Web offline | One worker owns offline and push. Complete content-addressed precache; local engine assets; no forced takeover of active editors; only OpenSplit caches are removed. |
| Navigation | Native `/app` links normalize to internal routes; authentication preserves the intended route; external return destinations are rejected. |
| Push | Web skips native notification plugins; explicit opt-out is respected; initialization is coalesced; background work reloads identity and cannot revive a cleared account. |
| Architecture | Provider composition split into backend, local storage, ledger, session, sync, push, routing, and platform modules. Token operations have a repository boundary. Existing Riverpod state management is retained. |
| Dependencies | Updated Drift/sqlite3 native assets and compatible code-generation tooling; removed the old direct SQLite bootstrap dependency. |
| UI foundation | Added localization infrastructure and shell strings; large-text and keyboard tests. This is not a claim that every string is localized or that screen-reader testing is complete. |
| Release tooling | Single web packaging command for static site, Flutter, and worker configuration; safe client-key checks; self-hosted HTTPS validation; pinned CI and manual artifact-only release workflow. |

## Verification

The latest full run and focused follow-up runs cover:

- 382 Flutter unit, repository, widget, screen-flow, and local Supabase adapter
  tests.
- 131 domain tests in Chrome, including exact-money allocation behavior.
- 193 PostgreSQL/pgTAP tests across seven files.
- Four JavaScript service-worker tests: complete install, offline app routes,
  request isolation, and cache ownership.
- Clean fatal-info Dart analysis, formatting checks, and Deno formatting/type
  checks for both Edge Functions.
- Wasm release web build with a JavaScript fallback and no engine CDN dependency.
- Local Firebase Hosting: static landing/terms, `/app` deep-link rewriting,
  expected 404s outside the app, Wasm isolation headers, desktop and 390px
  welcome layouts, and app reload with the hosting server stopped.

The browser used inert CI configuration. It did not sign into a real account,
send email, register push permissions, or perform a payment. The stopped-origin
reload is an offline-shell check, not a full browser-network-disconnection test.

## Outstanding release gates

1. **Android signing is blocked locally.** Release compilation reached packaging,
   which failed because macOS denied access to the configured
   `/Users/seenuk/Downloads/upload-keystore.jks`. Make the key readable to the
   build process and rerun the signed APK/AAB build. Do not substitute a debug
   signature for release verification or commit a keystore/password.
2. **An upstream build warning remains.** `in_app_review` 2.0.12 applies the old
   Kotlin Gradle plugin. The pinned Flutter 3.47.1 toolchain warns about future
   incompatibility. The warning is not an observed runtime defect, but the
   dependency must be upgraded or deliberately replaced before a Flutter
   upgrade that removes this support. It has not been silently patched in the
   package cache or vendored as an unmaintained fork.
3. **Exercise the real deployment integrations.** Google on Android and web,
   email OTP and identity linking, sign-out/account deletion, cold/warm App
   Links, foreground/background push and opt-out, and UPI cancellation/success
   handoff need the intended credentials and actual devices. Verify the Play
   signing certificate against `site/.well-known/assetlinks.json`.
4. **Run remote CI on the final commit.** These results are local. The manual
   release workflow packages artifacts after CI; it does not deploy them.
5. **Complete operational acceptance.** Backups/restore rehearsal, SMTP delivery,
   Auth abuse limits/CAPTCHA decisions, secret provisioning, monitoring/alerts,
   support ownership, and legal/store-listing review are deployment gates, not
   facts proven by a green unit-test run.

Android data-only background push deliberately does not refresh or persist
credentials. If the stored session has expired, synchronization waits for the
foreground SDK on app resume. This avoids competing refresh-token writers and
resurrecting a signed-out session; it also means timely background notification
delivery after a long idle period is not guaranteed. Confirm that product
trade-off in device acceptance testing.

The v1 PostgreSQL and local SQLite schemas were edited in place as requested.
Recreate disposable development databases/app storage before testing this
schema against an older checkout's data. Never use that reset approach once
real users exist.

## Primary references used

- [Service-worker lifecycle](https://web.dev/articles/service-worker-lifecycle):
  waiting/activation behavior and avoiding mixed active releases.
- [Firebase messaging in web apps](https://firebase.google.com/docs/cloud-messaging/web/receive-messages):
  sharing an existing service-worker registration with messaging.
- [Drift transactions](https://drift.simonbinder.eu/dart_api/transactions/):
  atomic local mutation and queue persistence.
- [Firebase API-key configuration](https://firebase.google.com/docs/projects/api-keys):
  public client identifiers and application restrictions.
- [In-app review changelog](https://pub.dev/packages/in_app_review/changelog):
  available upstream release history.
