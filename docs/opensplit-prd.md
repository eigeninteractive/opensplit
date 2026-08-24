# OpenSplit — Product Requirements Document

**Version** 1.0 · **Status** Locked for v1 build · **Date** 21 August 2026

---

## 1. Summary

OpenSplit is a free, open-source, local-first expense splitting app for Android and web, built in Flutter. It exists because every incumbent either paywalls the act of logging an expense (Splitwise) or has no real mobile app (Spliit, SplitPro, IHateMoney).

**Positioning:** the only open-source splitter with a genuinely native cross-platform client, instant offline-capable reads, and a credible promise of never paywalling core function.

**One-line pitch:** Split expenses with friends. Free forever, no ads, works offline, open source.

---

## 2. Goals

| # | Goal | Success measure |
|---|---|---|
| G1 | Logging an expense is faster than remembering to log it later | < 10s from app open to saved expense |
| G2 | Every read is instant | No spinner on any screen after first sync |
| G3 | Works fully offline | Full CRUD with no network; trips abroad are the primary use case |
| G4 | Costs stay near zero regardless of scale | < €25/mo at 100k users |
| G5 | Self-hosting is real, not aspirational | `docker compose up` → working instance, < 15 min |
| G6 | The app survives project abandonment | Data on device; app functions read-only if server disappears |

## 3. Non-goals for v1

Explicitly out of scope. Each was considered and rejected for a stated reason.

| Excluded | Reason |
|---|---|
| End-to-end encryption | Kills web share links, forces recovery-phrase onboarding, blocks debugging. Data model stays E2EE-*shaped* for a possible opt-in v2. |
| Splitwise import | Deferred to v2. Export CSV is lossy (net-per-person, not payers/shares); needs a fuzzy person-matching UI. |
| Receipt photos | Storage + egress dominate all other costs by orders of magnitude. This is exactly what forced Splitwise's paywall. |
| Receipt scanning / OCR | Per-call inference cost. Recurring per-user cost forces a paywall. |
| Bank connections (Plaid etc.) | Per-account, per-month, forever. Same trap. |
| Recurring expenses | Deferred to v2. Valuable (rent), not required to prove the product. |
| iOS | v2. Affects auth (Sign in with Apple becomes mandatory) and push (APNs silent-push throttling). |
| Weekly summary emails | Requires SMTP volume and server-side computation. |
| Server-side balance recompute / audit endpoint | Deferred. Client fold is the single source of display truth. |
| Group chat, payment processing, business/team features | Not the product. |

---

## 4. Principles

These are commitments, published in the repository as `PRINCIPLES.md`.

1. **Never gate the act of logging an expense.** No daily caps, no expense limits, no interstitials. This is the specific friction that cost Splitwise its goodwill.
2. **No ads. No analytics SDKs. No data sale.** Ever.
3. **No venture funding.** Splitwise did not paywall because its founders turned bad; it took money that mandated growth, which mandated extraction. This is the structural defense and everything else is detail.
4. **AGPL-3.0.** Prevents a proprietary hosted fork outcompeting the project it came from.
5. **If monetization ever happens, charge for convenience, never for function.** Hosted tier, one-time purchase, or sponsorship — never a feature gate.
6. **Self-hosting is a first-class path**, not a courtesy.

---

## 5. Users and core flows

**Primary:** groups of 2–10 friends, flatmates, or travellers settling shared costs. Mobile-first. India is the initial market (INR default, UPI settle-up), but multi-currency is core, not an add-on.

**Critical path — invite acceptance.** Most users arrive because a friend added them as a placeholder and sent a link. This flow must have zero walls:

```
Tap link → web or app opens at /join/:token
         → anonymous session created silently
         → claim placeholder member
         → land inside the group, balances visible
```

No signup screen. Identity linking is nagged later, never blocking.

**Other core flows:** create group → add members (some as placeholders) → add expense (equal / exact / shares / percent, one or many payers) → view balances → simplify → settle up → record settlement.

---

## 6. Feature scope — v1

**In:**
- Groups and direct (1:1) splits — a direct is internally a 2-member group, `is_direct = true`. There is no second system.
- Expenses: multiple payers, four split modes (equal, exact, shares, percent)
- Multi-currency with auto-fetched rates
- Balances (per currency) and simplify-debts
- Settlements, including UPI deep-link / QR handoff
- Categories and spend analytics
- Push notifications
- Offline-first with background sync
- Anonymous auth with optional upgrade
- Deep-linkable invites and group URLs
- CSV export

**Out:** everything in §3.

---

## 7. Architecture

```
┌───────────────────────────────────────────────┐
│  Flutter client  (Android + Web)              │
│                                               │
│  UI ── Riverpod 3 ── Repository ── Drift      │
│                          │        (SQLite)    │
│                          │                    │
│  All computation local:  │                    │
│   • split arithmetic     │                    │
│   • balance fold         │                    │
│   • simplify debts       │                    │
│   • analytics / search   │                    │
└──────────────────────────┼────────────────────┘
                           │ cursor sync (delta pull)
                           │ RPC writes
┌──────────────────────────┼────────────────────┐
│  Supabase                                     │
│   Postgres  — entries, RLS, invariant trigger │
│   Auth      — anon / Google / email OTP       │
│   Edge Fn   — FCM fan-out on insert           │
│                                               │
│  Server does NO business computation.         │
└───────────────────────────────────────────────┘
```

**The server is a paginated row feed.** It stores facts and enforces one invariant. It computes nothing.

This is a cost strategy as much as a UX one: reads outnumber writes roughly 50:1 in this app, and 100% of read cost sits on devices the user already paid for. It is also what makes self-hosting a weekend port rather than a reimplementation.

**Supabase sits behind a repository interface in Dart.** No `supabase.from(...)` calls outside `data/`. This makes the self-host promise real and gives an exit if Supabase's pricing moves — which is the exact failure mode being guarded against.

---

## 8. Data model

The schema lives in `supabase/migrations/`, twelve files organised by subject rather than by the date each was learned: foundation, currencies, identity, groups, entries, fx, invites, push, write path, security, grants, jobs.

### Core shape

```
profiles      — mirrors auth.users
groups        — name, default_currency, is_direct, simplify_debts
members       — group-scoped identity; profile_id NULL = placeholder
entries       — expense | settlement; amount in integer minor units
entry_payers  — a TABLE (multiple payers per bill)
entry_shares  — resolved amount + original weight
categories    — global presets + group overrides
currencies    — ISO 4217 with exponent
fx_rates      — one row per currency per day, all against a USD pivot
invites       — single-use claim tokens against a member row
device_tokens — FCM registrations, for the fan-out
```

No receipt photos in v1, so `entries` has no `receipt_path`. UPI payment identity
lives on `profiles`, not on `members`: a payment handle is personal, not
group-scoped, and it is visible to group members through the existing profiles
policy.

### The three load-bearing decisions

1. **Members are group-scoped, not auth users.** All financial rows reference `member_id`. A placeholder "Arun" is a first-class member with `profile_id IS NULL`; when he signs up you set one column and touch nothing else. Referencing `profile_id` would force a data migration every time someone joins.

2. **Shares store both the rule and the result.** `weight` (input — keeps "2:1:1" editable) and `amount_minor` (output — immutable historical fact). Store only the rule and a future rounding fix retroactively changes settled balances. Store only the amount and re-editing is impossible.

3. **Balances are a view, never a table.** `v_member_balances`, grouped by `(group_id, member_id, currency)`. A group can legitimately hold ₹500 and €20 simultaneously; collapsing to one display currency is a client-side view.

### The invariant

A deferred constraint trigger enforces `sum(payers) = sum(shares) = amount_minor` at COMMIT. It catches every rounding bug, every bad largest-remainder implementation, and every torn write — permanently, server-side. Stored data cannot drift even if client logic does.

### Rates are stored against a pivot, not as pairs

Both server-side and in the Drift mirror:

```sql
create table fx_rates (
  as_of    date    not null,
  currency char(3) not null,
  rate     numeric not null,   -- units of `currency` per 1 USD
  primary key (as_of, currency)
);
```

A pair table is O(n²) rows and makes "is EUR→INR supported?" a real question. A
pivot makes any pair a division of two lookups, so there is no such thing as a
supported *pair* — only a currency that has a rate on a date, or does not.

---

## 9. Auth and identity

**Providers (v1):** anonymous · Google (native ID token) · email OTP.

Sign in with Apple is **not** required in v1 — Apple's guideline 4.8 binds only on iOS, which is v2 scope.

**Anonymous is the default entry path.** `signInAnonymously()` creates a real `auth.users` row with an `is_anonymous` JWT claim. `linkIdentity()` / `updateUser(email:)` upgrades it later, preserving the same user ID, so no data migration on upgrade.

**Google:** native `google_sign_in` feeding `signInWithIdToken()` — not the OAuth web redirect. One tap, no browser bounce.

**Email OTP:** 6-digit code, **not** magic link. Magic links open in the wrong browser, lose app context, and get mangled by mail scanners. Requires custom SMTP (Resend or SES); Supabase's built-in mailer is dev-only and rate-limited.

**No SMS OTP**, despite being the Indian default. Per-message cost scales linearly with signups and never goes away, and SMS pumping fraud can generate a real bill overnight.

### Required guards

| Guard | Why |
|---|---|
| Rate limit on the anonymous endpoint | Anon sign-in is unauthenticated row creation. `anonymous_users = 30` per hour per IP. Deliberately not a CAPTCHA: it would sit in front of the one flow that has to be invisible, and an invite link that opens a puzzle is an invite link nobody follows. |
| Cleanup cron: delete anon users with no linked identity, no membership, > 30 days | Anonymous users count toward MAU |
| RLS gate on destructive actions | An anon user must not delete groups or remove members |
| Nag to link identity after the 3rd entry | Anon = one device, no recovery. On web, clearing site data destroys the account permanently. Copy must be blunt about this. |

```sql
create policy groups_delete on groups for delete to authenticated
  using (is_group_owner(id)
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false);
```

### Invites

A separate `invites` table. The link carries a **single-use, TTL'd claim token** — never a raw `member_id`, or anyone with the URL can seize someone's financial identity.

```
invites(token uuid pk, group_id, member_id, created_by,
        expires_at, redeemed_at, redeemed_by)
```

Redemption is an RPC: validate token → set `members.profile_id` → mark redeemed. Atomic.

---

## 10. Sync and offline

**Model:** client holds the full journal in Drift. Server holds `entries` + children. Client pulls deltas by cursor.

- **Read:** `select … where group_id = ? and updated_at > cursor order by updated_at limit N`
- **Write:** local write → outbox queue → `upsert_entry` RPC. `client_key` (uuid) makes retries idempotent — already in the schema.
- **Conflicts:** last-write-wins on `updated_at`, using server `now()`, never client clocks.
- **Ordering:** entries are independent facts; there is no cross-entry ordering requirement. This is why a full CRDT is unnecessary.

### Known trade-offs (accepted)

| Risk | Mitigation |
|---|---|
| **Client version drift** — an old app is old business logic; two users could see different balances for the same group | Stamp `algo_version` on entries; never retroactively change how old entries compute; enforce a minimum-version floor |
| Web cold start — no local DB on first visit; OPFS can be evicted | Paginate initial sync; render group list from a summary query while entries stream |
| Unbounded local growth | Lazy-load archived groups; don't sync everything on login |
| Concurrent offline edits silently drop one | Visible edit history so it's socially recoverable |
| Support is harder — "my balance is wrong" needs client state | Ship an export-debug-bundle button in v1 |

---

## 11. Push notifications

**Pattern: notification-as-sync-trigger.**

```
entries insert → database webhook → Edge Function
              → FCM data-only message
              → client wakes, pulls delta, computes
              → posts a LOCAL notification
```

```
"Ravi added Dinner at Toit — ₹2,400. Your share: ₹600."
```

"Your share" is a column read on `entry_shares.amount_minor` — no computation needed.

**Why local notifications:** the notification text is produced by the same Dart code that renders the screen, so they can never disagree. A server-side formatter would be a second implementation of currency and rounding logic, quietly drifting.

**Platform notes:** FCM is free at any volume reachable here. Android data-only messages work directly. Web requires `firebase-messaging-sw.js` in `web/`; Chrome/Firefox/Edge fine, Safari requires PWA install. iOS is v2 (silent pushes are throttled by design).

**Cost guard:** no persistent realtime subscriptions by default. Supabase bills on peak concurrent realtime peers. Push-to-wake replaces it. Live subscriptions are reserved for the rare case of two people editing the same group simultaneously.

---

## 12. Multi-currency

**Balances are always authoritative per currency.** Conversion is display only, never stored as a balance.

**Rate source:** Frankfurter (`api.frankfurter.dev`) — free, no API key, CORS-enabled, ECB reference data, includes INR. Client fetches directly; zero server cost. Fall back to an Edge Function proxy only if rate-limiting becomes a problem.

**Rules:**

1. **Never convert on write.** Store the original amount and currency, always.
2. Amounts are `bigint` minor units. **Exponent comes from the `currencies` table** — JPY is 0, KWD is 3. Hardcoding ×100 is a shipped bug.
3. On entry creation, capture a rate snapshot into `entries.fx_rate / fx_source / fx_at`. Semantics: rate to convert *entry currency → group default currency* at entry time. **Never re-fetch for historical entries** — the rate is a fact about the transaction.
4. Cache rates in the Drift `fx_rates` table keyed by date. Offline → use last cached rate and flag the displayed figure as approximate.
5. ECB publishes once per business day, no weekends. Acceptable for expense splitting; use the most recent published date.
6. **Simplify-debts runs per currency independently.** Cross-currency netting silently assigns FX risk to one party and must not happen by default.
7. Group summary may show a converted total, always visibly marked as an estimate, with the per-currency breakdown one tap away.

---

## 13. Settle up and UPI

Settlement is an `entry` with `kind = 'settlement'`, one payer and one share. Same table, same balance fold, excluded from spend analytics.

### UPI handoff (India)

Shown **only** when the settlement currency is INR and the payee has a `upi_vpa`.

```
upi://pay?pa=<vpa>&pn=<name>&am=<amount>&cu=INR&tn=OpenSplit%20settlement
```

| Platform | Behaviour |
|---|---|
| Android | Intent → UPI app chooser |
| Web | Render the same URI as a **QR code** — any UPI app can scan it |

**Critical honesty constraint:** the UPI intent returns no reliable confirmation. Payment cannot be verified. The flow is therefore:

```
Tap "Settle ₹600 to Priya" → UPI app opens → user pays → returns
  → OpenSplit asks "Did the payment go through?"
  → on confirm, records the settlement entry
```

Recording is explicitly manual. UI copy must never imply OpenSplit verified or processed a payment. OpenSplit is not a payment processor and handles no money.

Non-INR settlements record manually, with no payment handoff.

---

## 14. Deep linking

The same URL must work as a web route and an Android App Link. This forces two things.

```dart
void main() {
  usePathUrlStrategy();   // hash fragments are never sent to the server,
  runApp(...);            // so they cannot be App Links
}
```

Host must serve SPA fallback: all routes → `index.html`.

**Routes (one `go_router` table serves both platforms):**

```
/                    group list
/g/:groupId          group detail
/g/:groupId/e/:id    entry detail
/join/:token         invite claim
/auth/callback       OAuth return
/settings
```

**Android:**

```xml
<intent-filter android:autoVerify="true">
  <data android:scheme="https" android:host="opensplit.app" />
</intent-filter>
```

`assetlinks.json` at `/.well-known/`. **Must include the SHA-256 of both the upload key and the Google Play App Signing key**, or verification passes in debug and fails in production. Verify with `adb shell pm verify-app-links --re-verify <pkg>`; it fails silently otherwise.

**Payoff:** an invite link tapped by someone without the app opens the web build and just works — deferred deep linking for free, which normally requires a paid SDK.

---

## 15. Client architecture

**Stack:** Flutter · Riverpod 3 · Freezed · go_router · Drift.

Build web with `flutter build web --wasm`. WasmGC is stable and meaningfully faster than the CanvasKit JS path; Flutter emits a JS fallback for older browsers automatically.

**Layers:**

```
presentation/   widgets, screens
application/    Riverpod providers, view models
domain/         pure Dart — splitting, balance fold, simplify.
                No imports from data/ or Flutter.
data/           Drift DAOs, Supabase repository, sync engine.
                The ONLY place Supabase is referenced.
```

**Drift is the cross-platform key:** native SQLite on Android and `sqlite3.wasm` over OPFS on web, from identical Dart via `drift_flutter`. The repository layer does not branch.

### Web-specific requirements

- Wrap content in `SelectionArea` — unselectable text is the top "this isn't a real website" tell
- URL is state; every meaningful screen deep-linkable, browser back must work
- `NavigationBar` under 600dp, `NavigationRail` above
- Never import `dart:io`; use `kIsWeb` and conditional imports
- Real skeleton in `index.html` — the pre-first-frame gap is the worst impression the app makes

### Domain logic requirements

- **Splitting:** largest-remainder on integer minor units, deterministic tiebreak by sorting on `member_id`, so every device produces identical paise
- **Simplify:** net each member per currency, greedily match largest creditor against largest debtor. Run per currency. **Derived view only — never writes rows.** Must always drill from "you owe Arun ₹340" back to the entries that produced it; the top complaint about Splitwise's simplify is unexplainable debts.

---

## 16. Analytics (in-app)

All local SQL over Drift. Zero server cost, no endpoints, no cache invalidation.

- Spend by category (group and personal)
- Spend by member
- Spend over time
- Filter by date range, member, category, currency
- Full-text search over descriptions via **SQLite FTS5** — instant, offline. (Splitwise paywalled search.)
- CSV export of any filtered view

No third-party analytics SDK is present in the app. Product metrics come from aggregate database counts only.

---

## 17. Cost model

An entry plus payers and shares is roughly 600 bytes. 100k active users × 20 entries/year ≈ **1.2 GB/year**.

| Component | Cost |
|---|---|
| Postgres storage & compute | Supabase free tier → ~€20/mo dedicated at scale |
| Object storage | **€0** — no images |
| Realtime | Near €0 — push-to-wake, no persistent subscriptions |
| FCM | €0 |
| FX rates | €0 — Frankfurter, no key |
| Email (OTP only) | ~€1/mo — SES |
| Web hosting | €0 — static build on Cloudflare Pages |

**Cold-storage job:** any group untouched for 12 months has its entries serialised to a single compressed blob and only the summary kept hot, restored on demand. This holds the working set roughly flat regardless of cumulative signups — the property that makes "free forever" true rather than aspirational.

---

## 18. Quality bars

| Metric | Target |
|---|---|
| Cold start to interactive (Android) | < 1.5s |
| Web first contentful paint | < 2.5s |
| Any screen navigation | < 16ms frame budget, no spinner |
| Add expense, tap to saved | < 10s |
| Offline | Full CRUD, indefinite |
| `sum(balances)` per group per currency | Exactly 0, always |

---

## 19. Testing

**Domain layer — property-based tests are mandatory.** The splitting and balance logic is pure functions over immutable data. Generate thousands of random entry sets and assert:

- `sum(balances) == 0` per group per currency
- `sum(payers) == sum(shares) == amount` for every entry
- Largest-remainder is deterministic across shuffled member orderings
- Simplify preserves every member's net position exactly
- Round-trip: entries → balances → simplify → apply settlements → all balances zero

Thousands of cases run in milliseconds with no database and no network. In a money app this is the difference between "probably correct" and "provably correct" — and it is the main reason the fold lives in Dart rather than in Postgres views.

**Integration:** RLS policy tests (especially that `is_group_member` does not recurse — error 42P17 is the standard Supabase failure here), invariant trigger rejection tests, sync convergence, offline→online replay.

---

## 20. Milestones

| M | Scope | Exit criteria |
|---|---|---|
| **M0** | Local-only, single-user. Drift schema, domain logic, splitting, multi-currency, balances. | Property tests green. No network code exists. |
| **M1** | Settle-up UX + simplify + UPI handoff. | A flatmate group can be settled end to end, offline. |
| **M2** | Supabase schema, RLS, RPC, cursor sync, outbox. | Two devices converge. Invariant trigger rejects bad writes. |
| **M3** | Auth (anon → Google / OTP), invites, claim tokens. | Invite link → in-group in < 15s with no signup. |
| **M4** | Push, categories, analytics, CSV export. | Feature complete. |
| **M5** | Web build (`--wasm`), deep links, `assetlinks.json`, Play Store. | App Links verify in production. Public launch. |

M0–M1 are the product. M2 is the part most projects start with and shouldn't — most splitting apps die on the settle-up flow, not the architecture.

---

## 21. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Anonymous auth abuse | High | Per-IP rate limit on the anon endpoint; cleanup cron deletes accounts that never joined a group |
| Client version drift produces divergent balances | Low | Shares are stored, not recomputed, so a rounding change can never move a settled entry. The server's deferred trigger rejects any entry that does not balance, whatever wrote it. `v_member_balances` is the independent second implementation that pgTAP checks the Dart fold against. |
| App Links fail in production only | Medium | Both signing key hashes in `assetlinks.json`; verify with `adb` pre-release |
| Flutter web perceived quality | Medium | WasmGC, `SelectionArea`, real HTML skeleton, URL-as-state |
| Users lose anonymous accounts | Medium | Nag to link after 3rd entry; blunt warning copy on web |
| Supabase pricing changes | Low | Repository interface; self-host path tested each release |
| UPI mistaken for payment processing | Medium | Explicit "did it go through?" confirmation; copy never implies verification |

---

## 22. v2 backlog

Ordered by expected value:

1. **iOS** — adds Sign in with Apple (mandatory once shipped) and APNs
2. **Splitwise CSV import** — the migration path is the adoption path
3. **Recurring expenses** — rent and bills; the top requested feature in this category
4. **Opt-in per-group E2EE** — private groups lose web links, gain encryption; normal groups keep the frictionless path
5. **Desktop builds** — macOS / Windows / Linux, nearly free from the same codebase
6. **Self-host reference server** — Go + Postgres, no Supabase dependency

---

## Appendix — decision log

| Decision | Rationale |
|---|---|
| Centralised server, not P2P | Pure P2P fails on availability (peers rarely online simultaneously), NAT traversal under CGNAT, push, and recovery. "No server" was never true — only "someone else's server". |
| Not Nostr / Matrix / atproto / IPFS | Relay durability is unguaranteed; expense history is a multi-year financial record. Key recovery is impossible by design. Onboarding kills consumer adoption. |
| Decentralise the protocol, not the topology | Narrow API + self-host + open schema gives credible exit without volunteer-infrastructure risk. |
| No Beancount / hledger adoption | Double-entry is the right *discipline* and the invariant is worth keeping, but the format is a poor *storage* model: split rules have no home (the ecosystem smuggles them into tag strings), it assumes a single entity, and it encodes identity as account-name strings. |
| Balances derived, never stored | SplitPro v2 shipped this migration after hitting stale-balance bugs. Free lesson. |
| Client-side computation | Reads outnumber writes ~50:1; moving them to devices is what makes free-forever credible. Also makes self-hosting a weekend port. |
| Local notification, not server-formatted | Prevents a second implementation of currency and rounding logic drifting from the UI. |
