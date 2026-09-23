# Moving OpenSplit to Cloudflare

A clean cutover, not a port. The Supabase backend is deleted, not adapted, and
the Cloudflare one is written as though it had always been the backend.

This document is the plan. `docs/cloudflare-architecture.md` is the design
sketch it implements; that file gets rewritten from "proposed" to "this is what
runs" in the final phase.

---

## Decisions taken before writing any code

| Question | Answer | Why |
|---|---|---|
| Where it is served | `opensplit.eigeninteractive.com`, one Worker, one origin | Site, app and API on one host: no CORS, no cross-site cookies, one deploy. Free, on a zone already on Cloudflare. |
| Sync protocol | Rebuilt around a per-group sequence number | The Durable Object serializes writes, so it can hand out a monotonic `seq`. One request and one integer replace four requests and four `(updated_at, id)` keyset cursors per group. |
| Sign-in codes | Resend, behind a one-function interface | Cloudflare Email Sending is **Workers Paid only**. Resend's free tier is 3,000/month and 100/day, and `support.eigeninteractive.com` is already verified there. Swapping to `env.EMAIL.send()` later is one file. |
| Guest → account | Link in place, user id preserved | `linkSocial({idToken})` and email-OTP `changeEmail` on the live session, then clear `isAnonymous`. No member row in any Durable Object is ever rewritten. Better Auth's anonymous-plugin migration path is deliberately not used. |
| Session transport | `HttpOnly` cookie on web, bearer token on Android | Same origin makes a first-party cookie the stronger option on web — JavaScript cannot read it, so a compromised dependency cannot steal the session. Android has no cookie jar a background isolate can reach, so it carries a token. One session, one server config; see *Auth*. |
| Plan | Workers Free to start | Durable Objects with SQLite storage are on Free: 100k requests/day, 13,000 GB-s/day, 5M rows read/day, 100k rows written/day, 5 GB stored. See *Limits that shape the design*. |
| ORM and migrations | Drizzle + drizzle-kit, for D1 **and** the Durable Object | One TypeScript schema is the source of truth; `drizzle-kit generate` emits the SQL. No migration is written by hand. `drizzle-orm/durable-sqlite` maps `db.transaction()` straight onto `ctx.storage.transactionSync()` in sync mode, so the balance invariant keeps the atomicity it depends on. |
| Validation and contract | Zod 4 + `@hono/zod-openapi` | One Zod schema per payload is the validator, the TypeScript type and the OpenAPI definition. The spec is emitted at 3.0.3 and committed; CI fails on drift. |
| Dart client | Generated from the spec by `openapi_generator` (OpenAPITools, `dart`/http target) | Plain classes over `package:http` — no built_value, no dio, no chopper — which is the only generated stack that does not fight the pubspec's minimalism. Replaces the hand-written `wire.dart`; `mappers.dart` still translates to the freezed domain models. Costs a JDK in the codegen path. |
| Router | Hono | The de facto Workers router; Better Auth mounts on it directly, and `@hono/zod-openapi` is the maintainers' recommendation for new projects. |
| Lint and format | Biome, matching the other Cloudflare projects | `biome.jsonc`: two-space indent, `lineWidth` 320, double quotes, trailing commas, `preset: "recommended"` — the same settings as `eigen-server` and `eigen-platform/server`. Generated files (`src/auth-schema.ts`, `migrations/meta`, `worker-configuration.d.ts`) are excluded or formatting them would fight the drift checks; `package.json` is excluded because npm rewrites it on every install. The repo-root `.vscode/settings.json` points the editor at `server/node_modules`, so editor, CLI and CI run one binary. |
| Self-hosting | Withdrawn, and said so plainly | Durable Objects, D1 and KV are not products anyone can stand up. The server is written in the shape Cloudflare wants, with no portability seam, and PRINCIPLES.md #6 is rewritten rather than quietly left standing. See *The promise that does not survive*. |
| Cloud resources | Created by you, from a runbook | Everything is built and verified against `wrangler dev` with local D1, KV and Durable Objects. Nothing here touches the account; the commands that do are collected in `docs/cloudflare-runbook.md`. |

Everything else in this document follows from those.

---

## The shape of it

```
                    opensplit.eigeninteractive.com
                                 │
                    ┌────────────┴────────────┐
                    │      one Worker         │
                    │  Hono + Better Auth     │
                    └────────────┬────────────┘
        ┌────────────┬───────────┼───────────┬─────────────┐
        │            │           │           │             │
   static assets   D1        Group DO      Fx DO          KV
   site/ + /app/  auth,     one per       singleton    fx month
                  profiles,  group,       rate writer  blobs
                  index,     SQLite
                  tokens
```

- **Static assets** — `site/` at the root, the Flutter web build under `/app/`,
  `_headers` carrying COOP/COEP and cache rules, `.well-known/assetlinks.json`.
  Assets are served ahead of the Worker, so a request for `main.dart.js` never
  invokes it. Only `/api/*` and SPA deep links (`/app/join/:token`) fall
  through to the Worker script, which routes the former and answers the latter
  with `/app/index.html` from the `ASSETS` binding.
- **Group Durable Object** — one per group, `idFromName(groupId)` on the
  client-generated group UUID. Owns members, entries, payers, shares, events,
  invites and the group's own row. The authorization boundary.
- **Fx Durable Object** — a singleton. The only writer of exchange rates, so
  the daily cron and an on-demand backfill cannot lose each other's updates.
- **D1** — Better Auth's tables, `profiles`, a `memberships` index, device
  tokens, and a token → group lookup for people who are not members yet.
- **KV** — FX month blobs only. Read-heavy, edge-cached, immutable once a
  month is past.
- **Bundled JSON** — currencies and categories. A couple of dozen rows that
  change about never; they are a module in the Worker, not a storage product.
  Changing them is a deploy, which is honest.

---

## Why the Durable Object is the whole design

The current authorization model is not "RLS is on". It is `auth.uid()` threaded
through every policy, two `SECURITY DEFINER` helpers, and two trigger-based
column guards standing in for what RLS cannot express. None of it ports: D1 is
SQLite, with no roles, no RLS and no `auth.uid()`.

What replaces it is not a translation of the policies. It is that **a Durable
Object processes one request at a time and owns exactly one group's data**, so
three separate pieces of Postgres machinery collapse into ordinary code:

- The deferred constraint trigger enforcing `sum(payers) = sum(shares) =
  amount` becomes one function called inside `ctx.storage.transactionSync()`,
  with the finished shape in hand. No deferral, because there is no moment
  where the write is half-applied and visible.
- `guard_group_update` and `guard_member_update` — which exist because RLS can
  gate rows but not columns, and `WITH CHECK` cannot see `OLD` — become plain
  comparisons with real `before` and `after` values, and a refusal that can say
  what it refused.
- `is_group_member()` becomes "look at my own member table". No recursion to
  design around, no `SECURITY DEFINER` to break the cycle.

And one thing that was not previously possible becomes free: a strictly
increasing sequence number per group, because there is exactly one writer.

### The sequence number

Every row written by the DO takes `seq = ++counter`. The change feed is
`WHERE seq > ?` across four tables, merged and ordered. That replaces:

- four cursors per group, each a `(timestamp, id)` pair;
- the row-value comparison spelled out by hand because PostgREST has no syntax
  for `(updated_at, id) > (?, ?)`;
- the quoting rule that made an unquoted ISO-8601 timestamp inside an `or=(…)`
  group silently match nothing;
- `ascending: true` having to be stated because the SDK defaults to descending;
- the whole class of bug where a row bumped mid-sweep moves past the cursor.

None of those were bad code. They were the cost of paging a multi-writer store
by timestamp, and that cost is now gone. `deleted_at` tombstones and `left_at`
mean nothing is ever hard-deleted, so a seq-ordered feed is complete by
construction.

### Nothing is computed on the server

Unchanged, and worth restating because it is what makes the Durable Object
cheap: balances, debt simplification, split arithmetic and analytics stay on
the device. `v_member_balances` is not ported as a view. The DO computes a
balance in exactly one place — deciding whether a member can be removed by
somebody else — and that is a fold over its own rows.

---

## Durable Object: `Group`

### Storage

```sql
-- one row; the group itself
meta(id, name, default_currency, is_direct, simplify_debts,
     created_by, created_at, archived_at, updated_at, seq)

members(id PK, profile_id, display_name, upi_vpa,
        joined_at, left_at, updated_at, seq)

entries(id PK, kind, description, category_id, currency, amount_minor,
        entry_date, split_kind, fx_rate, fx_source, fx_at, notes,
        created_by, client_key UNIQUE, created_at, updated_at,
        deleted_at, seq)

entry_payers(entry_id, member_id, amount_minor, PK(entry_id, member_id))
entry_shares(entry_id, member_id, amount_minor, weight_micros,
             PK(entry_id, member_id))

events(id PK, actor_id, created_at, kind, subject_id, payload, seq)

invites(token PK, member_id, created_by, created_at, expires_at,
        redeemed_at, redeemed_by)
group_link(token PK, created_by, created_at, expires_at, revoked_at)

counter(name PK, value)        -- 'seq'
index_outbox(id PK, kind, payload, attempts)
```

Payers and shares carry no `seq` of their own: they are part of the entry and
travel with it, which is also what the wire format already assumes.

Schema is a Drizzle schema compiled by `drizzle-kit` with
`driver: "durable-sqlite"`. The generated SQL is bundled into the Worker as
text (a `rules` entry for `**/*.sql`) and applied by `migrate()` from
`drizzle-orm/durable-sqlite/migrator` inside `blockConcurrencyWhile` on first
access after a deploy.

This is the DO analogue of `supabase/migrations`, and it needs its own test: an
object created at v1 and opened by v3 code must arrive at v3 with its rows
intact. Migrations here are lazy and per-object — a group nobody has touched
for six months migrates on its next open — which is the property that makes
that test worth having.

### Methods (RPC, not `fetch`)

```ts
changesSince(since: number, limit: number): ChangePage
upsertEntry(input: EntryInput, baseSeq: number | null): Entry
deleteEntry(entryId: string, baseSeq: number): Entry
putGroup(input: GroupInput): Group        // create, rename, archive, settings
putMember(input: MemberInput): Member
createInvite(memberId: string): Invite
peekInvite(token: string): InvitePreview | null
redeemInvite(token: string, profileId: string): Member
createGroupLink(): GroupLink
revokeGroupLink(): void
peekGroupLink(token: string): GroupLinkPreview | null
placeholders(token: string): Placeholder[]
joinWithLink(token, profileId, memberId?, displayName?): Member
forgetProfile(profileId: string): DeletionOutcome   // account deletion
maybeArchive(after: Duration): boolean              // cron
purgeIfSettledAndDormant(after: Duration): boolean  // cron
```

The Worker resolves the session, checks the D1 membership index as a first
pass, then calls the stub. **The DO re-checks membership itself and is the
authority** — the same defence-in-depth as today's policy-plus-trigger pair,
relocated. The D1 check exists to fail cheap, not to decide.

### The rules being ported, explicitly

These are the pgTAP-covered rules. Each becomes a guard in the DO with a test
that names it:

- An entry must balance: `sum(payers) = sum(shares) = amount`.
- An entry may never be hard-deleted; deletion sets `deleted_at`.
- An entry id belonging to another group cannot be rewritten in place.
- Authorship is the caller's own member row. There is no parameter for it.
- A group's `id`, `created_at` and `created_by` cannot be rewritten. `created_by`
  is set once at creation, and is an authorization, not a description.
- A member cannot be moved between groups or re-identified; `joined_at` is fixed.
- `profile_id` transitions only `null → yourself` (the invite claim), plus the
  one exception of an account being deleted, which sets it back to `null`.
- `display_name` and `upi_vpa` are editable on your own row and on any
  placeholder, and on nobody else's — including by the group's creator. This is
  the rule that stops a settle-up handoff paying the wrong person.
- `left_at` is always yours to set on yourself. Setting it on somebody else
  requires them to be settled in every currency.
- Events are written by the DO from what it committed. There is no client-facing
  write path to `events`, and no diff on the wire — only the entry's shape at
  each moment, with the difference derived on the device that reads it.
- An entry snapshot that is byte-identical to the previous one appends no event.
  One save that touches an entry and four shares must produce one event, not five.
- Adding an expense to an archived group un-archives it, and records that as the
  expense it was, not as "somebody restored the group".

### Conflict detection

`baseSeq` replaces `p_base_updated_at`, and the predicate is unchanged: a stale
base is refused **only when applying the write would move money**. Two people
fixing a typo do not arbitrate; an edit carrying a stale amount does. The
comparison is between two canonical `{amount, payers, shares}` shapes, ordered
by member id, weights excluded.

Refused with HTTP 409 and `{"error":{"code":"stale_base"}}`. The
`PT409`-versus-`40001` problem does not exist here — there is no PostgREST to
reinterpret a SQLSTATE — but the distinction it protected does, and the client
still maps it to `RejectionKind.stale`.

### Write-through to the D1 index

Membership changes write an `index_outbox` row in the same transaction, then
flush to D1 immediately after commit. A failed flush sets an alarm and retries
with backoff; the D1 writes are idempotent upserts, so at-least-once delivery is
enough. A weekly cron reconciles: every group in the index is asked to confirm
its own member list.

The DO is the truth. D1 is a derived index, and is allowed to be briefly stale
in exactly one direction — a first-pass check that says "no" when the DO would
say "yes" costs a retry, never a wrong answer.

---

## Durable Object: `Fx`

Singleton, `getByName("global")`. Holds `fx_rates(as_of, currency, rate,
source)` in its own SQLite and is the only writer of the KV month blobs.

- The daily cron calls `refresh()`, which walks the provider registry ported
  from `supabase/functions/fetch-fx` and publishes `fx:YYYY-MM` to KV.
- `backfill(asOf, currency)` covers an expense backdated past what is held. It
  refuses dates already covered, repeats within the hour, and anything past a
  global ceiling — the throttling that `request_fx_backfill` does today, but in
  the object rather than in a table plus a trigger.

A singleton DO rather than writing KV from two places, because KV is
last-write-wins and a cron run overlapping a backfill would silently drop a
rate. One writer is the cheap fix, and it is the fix this platform is for.

---

## D1

Better Auth owns `user`, `session`, `account`, `verification` and its plugin
tables, through its **Drizzle adapter** rather than the built-in D1 one. Its
schema is emitted as a Drizzle schema file by `auth generate` and committed;
`drizzle-kit generate` then turns the whole schema — auth tables and ours —
into one migration set. One pipeline, no hand-written SQL.

The cost, stated plainly: a Better Auth upgrade is now two steps — regenerate
its schema file, then `drizzle-kit generate` — and the generated file has to be
reviewed rather than trusted.

Ours:

```ts
profiles(id PK, displayName, upiVpa, updatedAt, deletedAt)
memberships(profileId, groupId, leftAt, updatedAt, PK(profileId, groupId))
deviceTokens(token PK, profileId, platform, updatedAt)
linkTokens(token PK, groupId, kind)    // 'invite' | 'group_link'
```

`profiles` is kept separate from Better Auth's `user` rather than folded in with
`additionalFields`. Auth tables are the generator's to rewrite; application data
should not be in the blast radius of a Better Auth upgrade.

`profiles` rows are created by a `databaseHooks.user.create.after` hook — the
replacement for `handle_new_user()`.

`link_tokens` exists because redemption happens before membership: somebody
holding a token has to be routed to a group they cannot yet read.

---

## Auth

Better Auth in the Worker, D1 as its database.

### One session, two transports

The session token is the same value on both platforms. How it travels is not,
and the difference is forced by what each platform is rather than chosen:

- **Web: an `HttpOnly; Secure; SameSite=Lax` cookie.** Now that the API is the
  same origin as the app, this is the stronger option, not the legacy one —
  JavaScript cannot read the token at all, so a compromised dependency cannot
  exfiltrate it, which `localStorage` cannot promise. The XSS surface here is
  narrow to begin with, because Flutter renders to canvas and there is no DOM
  to inject into; what remains is a bad dependency or a compromised host, and
  `HttpOnly` is aimed exactly at those. Cookies reintroduce CSRF, covered by
  `SameSite=Lax` plus Better Auth's own protection: every state-changing call
  is a POST/PUT/DELETE with a JSON content type, which `Lax` already refuses
  cross-site.
- **Android: a bearer token in `shared_preferences`.** Not a browser, so there
  is no persistent cookie jar — and more decisively, the FCM background isolate
  that syncs on a push wake starts cold and can only see `shared_preferences`.
  Cookies there would mean hand-rolling cookie persistence, which is a bearer
  token with extra steps.

Better Auth's `bearer` plugin accepts `Authorization: Bearer …` and falls back
to the cookie, so the server is configured once and the split lives in one Dart
file behind `kIsWeb`.

Plugins: `anonymous`, `emailOTP`, `bearer`.

### Identity endpoints are ours, not Better Auth's, on purpose

The client does not call `/api/auth/*` for the three flows that matter. It calls
three thin endpoints that wrap Better Auth's **server** API:

```
POST /api/identity/google    { idToken?, nonce?, allowSignIn }
POST /api/identity/email     { email }          -> { flow }
POST /api/identity/email/verify { email, code, flow }
```

Each returns `{ outcome: "kept" | "replaced", strandedUserId?, token }`.

This is the single most important decision in the auth work. The link-then-
recover logic — try to attach the identity to the session in hand, fall back to
signing in only when the identity provably belongs to somebody already, and
report which happened — currently lives in 400 lines of Dart that no test can
reach without a backend. Moving it to TypeScript puts it where `vitest` can
drive every branch, and leaves the Dart side as a transport.

The rules it encodes, unchanged:

- **With no session**, there is nothing to attach to and nothing at stake:
  `signIn.social({idToken})` or `signIn.emailOtp`. For a new address that is a
  sign-up, which is the request.
- **With a session**, try `linkSocial({provider, idToken})` or the email-OTP
  `changeEmail`. Both preserve the user id, so every group on the device stays
  with the account that wrote it. On success, clear `isAnonymous`.
- **`account_not_linked`** means that identity is already somebody's. Refuse
  with `IdentityAlreadyInUse` unless `allowSignIn` is set — the caller has to
  stop and say what signing in would cost, because by the time the session is
  replaced it is too late to ask.
- **With `allowSignIn`**, sign in, and compare the resulting user id against the
  previous one to decide `kept` versus `replaced`. Signing in with Google using
  the address an existing email account owns lands on *that same account* —
  the sign-in branch ran and nothing moved. Only the ids settle it.
- The email fallback uses `disableSignUp: true`. The default would silently mint
  an empty account and strand every group on the device.

`EmailFlow`, `IdentityOutcome`, `SessionKept`, `SessionReplaced` and
`IdentityAlreadyInUse` survive in `domain/` exactly as they are. That contract
was hard-won and the backend change does not touch it.

### Google on the web

Still a full-page redirect, because `COOP: same-origin` severs `window.opener`
and a popup could not talk back. But with the cookie transport there is no
token hand-off to arrange: the page leaves for Google, returns to
`/api/auth/callback/google`, Better Auth sets the session cookie on this origin,
and a 302 lands on `/app/welcome?from=…` already authenticated.
`PendingIdentityRedirects` stays as-is — it is what makes a refusal that
arrives after a round trip recoverable.

Two alternatives were considered and rejected for the cutover:

- **`COOP: restrict-properties` + `COEP: credentialless`** keeps cross-origin
  isolation while allowing popup `postMessage`, which would permit a popup
  sign-in. Chrome 116+ only; Firefox and Safari do not implement it, and an
  unrecognised COOP value degrades to `unsafe-none` — so those engines would
  silently lose cross-origin isolation, dropping Drift off its
  SharedArrayBuffer OPFS path and Flutter off its threaded renderer. Two
  engines' storage and rendering for a popup on the third is a bad trade.
- **FedCM** (`navigator.credentials.get()`) is browser-mediated, needs no
  opener channel, works under `COOP: same-origin`, and returns an ID token —
  the same input `linkSocial({idToken})` already takes on Android. It is the
  right long-term answer and is Chrome-first, so the redirect has to exist as a
  fallback regardless. Revisit after the migration, behind a capability check.

Redirect URI to register in Google Cloud:
`https://opensplit.eigeninteractive.com/api/auth/callback/google`.

### Email codes

Eight digits, ten-minute expiry, three attempts, sent by Resend from
`support.eigeninteractive.com`. A code and not a magic link, for the reason
already written down: links open in whichever browser the mail app prefers,
lose the app's context, and get consumed by corporate scanners. The Supabase
email templates are replaced by two small HTML/text strings in the Worker.

### Account deletion

`DELETE /api/account`: read the caller's groups from the index, ask each DO to
`forgetProfile()` — which sets `profile_id` back to `null`, keeping the
membership as a placeholder with the name intact so co-members' balances and
history are untouched — delete outright any group nobody else could ever read
again, then delete the profile, device tokens and Better Auth rows. The session
is left alone; the caller decides what to do with the device.

---

## The client API

One request per group per sync, down from four.

```
GET    /api/bootstrap                          my profile + group ids + reference etag
GET    /api/groups/:id/changes?since=&limit=   group + members + entries + events
POST   /api/groups/:id/entries                 upsert (idempotent on clientKey)
DELETE /api/groups/:id/entries/:entryId        soft delete
PUT    /api/groups/:id                         create / rename / archive / settings
PUT    /api/groups/:id/members/:memberId       member upsert
GET    /api/profiles?since=                    profiles I can see
PUT    /api/profile                            my name and payment handle
GET    /api/reference                          currencies + categories (cached, ETag)
GET    /api/fx?since=YYYY-MM-DD                rates at or after a date
POST   /api/fx/backfill                        fire and forget
POST   /api/devices        DELETE /api/devices/:token
GET    /api/links/:token                       peek, no session required
POST   /api/links/:token/join                  redeem or join
POST   /api/groups/:id/invites                 mint a per-member invite
POST   /api/groups/:id/link  DELETE /api/groups/:id/link
DELETE /api/account
```

`changes` returns:

```json
{ "seq": 412, "hasMore": false,
  "group": { … } | null, "members": [ … ], "entries": [ … ], "events": [ … ] }
```

Every request and response body is a Zod schema, registered with
`@hono/zod-openapi`, so one declaration is the runtime validator, the
TypeScript type and the OpenAPI definition at once — there is no second place
for the wire format to be described, and therefore nowhere for it to drift.

Errors are `{"error":{"code","message"}}` with a status. The client maps
409 → `stale`, 400/403/404/422 → `permanent`, 5xx and transport → `transient`.
That replaces the SQLSTATE lookup table in `_translate`, and it is a better
boundary: the server states the kind rather than the client inferring it from a
Postgres error code.

The spec is served at `/api/openapi.json`, emitted as **OpenAPI 3.0.3** rather
than 3.1 — nothing here needs 3.1, and 3.1 support across Dart generators is
uneven. It is committed to `docs/openapi.json` and regenerated in CI, which
fails on a diff, so a change to the wire format cannot land without showing up
in review as a change to the contract. That is the same discipline
`drift_schemas/` already gets.

`/api/reference` and `/api/fx` are the two responses worth caching at the edge;
both are identical for every user, which is what `using (true)` said in SQL.

---

## Push

The DO calls FCM v1 directly, wrapped in `ctx.waitUntil()`, after its own write
has committed. This replaces `notify-event`, the `pg_net` dispatch and the
`trg_group_events_notify` trigger.

- Which kinds wake a device: `entry`, `member_joined`, `member_left`. Not
  renames, archives or links — those belong in the feed, which is read on
  purpose, rather than on a lock screen.
- Recipients: the DO knows its members; device tokens are one indexed D1 query,
  excluding the actor. On an edit the actor and the author are usually different
  people, and the author is precisely who needs to know.
- Payload: ids and a kind. No amount, no name, no description. The device says
  the rest, from the same formatter the screens use, after it has synced.
- The FCM OAuth token is minted with `jose` and cached in KV with a TTL, so a
  hundred group objects do not each mint their own.

No Queue. Notification volume is proportional to ledger writes, not to app
opens, so it was never the cost driver; an awaited `fetch()` yields the event
loop, so a pending send does not stall the next expense write. If reliability
ever needs to be tighter, `ctx.waitUntil(fetch(…))` becomes `env.QUEUE.send(…)`
behind the same call site and nothing upstream changes.

Firebase stays, for FCM only. Android has no alternative worth having, and the
web already uses the same SDK. Firebase Hosting, `firebase.json` and `.firebaserc`
are deleted.

---

## Cron

One Worker, three schedules:

- `0 4 * * *` — FX refresh via the `Fx` DO.
- `30 4 * * *` — archive and purge sweep. Candidate group ids come from the D1
  index; each DO decides its own fate and deletes its own storage. Replaces the
  `pg_cron` job calling `purge_settled_dormant_groups`.
- `0 5 * * 0` — abandoned anonymous accounts, and index reconciliation.

---

## Limits that shape the design

Workers Free, which is where this starts:

| | Free | Note |
|---|---|---|
| Worker requests | 100,000/day | Why `changes` is one request, not four. |
| CPU per request | 10 ms | Page size capped at 200 rows; no heavy JSON building. |
| Subrequests | 50/request | Fan-out to FCM batches. |
| DO requests | 100,000/day | |
| DO duration | 13,000 GB-s/day | |
| DO SQLite | 5 M rows read/day, 100 k written/day, 5 GB | 10 GB per object. |
| D1 | 5 M rows read/day, 100 k written/day | Enforced since Sep 2026. |
| KV | 100 k reads/day, 1 k writes/day | FX writes once a day. |

The 10 ms CPU ceiling is the one to watch, and it is the reason sessions are
**not** cached in KV to begin with: a D1 row read per request is I/O, which does
not count against CPU. Workers Paid ($5/month) lifts CPU to 30 s and removes the
daily request cap; that is the upgrade trigger, not storage.

---

## Repository layout

```
server/
  wrangler.jsonc
  package.json              pinned versions, npm ci in CI
  drizzle.d1.config.ts      dialect sqlite, out: migrations/
  drizzle.do.config.ts      driver durable-sqlite, out: src/do/migrations/
  src/
    index.ts                Hono app, routing, SPA fallback
    auth.ts                 Better Auth config (drizzle adapter)
    auth-schema.ts          GENERATED by `auth generate`; do not edit
    db/d1/schema.ts         profiles, memberships, device tokens, link tokens
    db/group/schema.ts      the Durable Object's tables
    schemas/                Zod payloads — validator, type and spec in one
    api/                    route modules, one per resource
    identity/               the three link-or-sign-in endpoints
    do/group.ts             the Group Durable Object
    do/fx.ts                the Fx Durable Object
    do/migrations/          GENERATED by drizzle-kit, bundled as text
    fx/providers/           ported from supabase/functions/fetch-fx
    push/fcm.ts
    email/sender.ts         behind an EmailSender interface
    data/currencies.json    data/categories.json
  migrations/               GENERATED by drizzle-kit; applied by wrangler d1
  test/                     vitest, running in workerd
```

Three directories are generated and none of them is hand-edited:
`src/auth-schema.ts`, `src/do/migrations/` and `migrations/`. The first comes
from `auth generate`, the other two from `drizzle-kit generate`.

`supabase/` is deleted in the final phase, whole.

### Configuration, by CLI

```sh
npm create cloudflare@latest server -- --category=hello-world \
  --type=hello-world-durable-object-with-assets --lang=ts
npx wrangler d1 create opensplit
npx wrangler kv namespace create FX

npm run auth:generate                    # -> src/auth-schema.ts
npm run db:generate                      # drizzle-kit -> migrations/
npm run db:generate:do                   # drizzle-kit -> src/do/migrations/
npm run db:migrate:local                 # wrangler d1 migrations apply --local

npx wrangler secret put BETTER_AUTH_SECRET
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put FCM_SERVICE_ACCOUNT
npx wrangler deploy
```

The CLI package is `auth`, not `@better-auth/cli` — the latter is deprecated as
of 1.4.21 and predates the version in use here.

Migrations are **generated** by drizzle-kit and **applied** by wrangler.
drizzle-kit's own `migrate` would need the `d1-http` driver, an API token and an
account id; generating locally and applying with the tool that already has the
binding keeps the whole loop offline.

`wrangler.jsonc` declares Durable Objects with the modern **`exports`** field
(`{"Group": {"type": "durable-object", "storage": "sqlite"}}`), not the legacy
`migrations` array. Once deployed with `exports` there is no going back to the
array, which is fine: this is a new namespace.

---

## Client changes

Contained. 16 files in `lib/` mention Supabase; `domain/` mentions it nowhere,
which is what makes this a swap rather than a rewrite.

**New** — `lib/data/api/`: an HTTP client (bearer, refresh, error mapping),
`CloudflareLedgerApi`, `CloudflareInviteApi`, `BetterAuthService`,
`CloudflareDeviceTokenRepository`, `SessionStore`.

**Rewritten**

- `config.dart` — `API_BASE_URL` replaces `SUPABASE_URL` and
  `SUPABASE_PUBLISHABLE_KEY`; `LINK_HOST` becomes
  `opensplit.eigeninteractive.com`. `configurationProblem` keeps doing its job
  against the new default.
- `sync_cursor.dart` — a cursor is an `int`.
- `change_feed.dart`, `feeds.dart` — four feeds per group collapse into one
  `GroupChangeFeed` applying a bundle in one transaction. The dirty-row and
  last-write-wins guards survive unchanged; they protect against a pull
  overtaking an unpushed local edit, which is still possible.
- `sync_engine.dart` — one drain loop per group instead of four.
- `session_storage.dart`, `background_handler.dart` — on Android, a bearer
  token in `shared_preferences` instead of a GoTrue session blob, with the rule
  that only the foreground refreshes it unchanged. On web there is nothing to
  store: the browser holds the cookie, and "am I signed in" is a request.
- `backend_providers.dart` — same providers, new constructors.

**Local database** — `schemaVersion` bumps, `onUpgrade` drops the sync cursor
table so every group re-syncs from zero, and leaves ledger rows and the outbox
alone. Then the committed contract is regenerated:

```sh
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

**Dependencies** — `supabase_flutter` out, `http` in. `google_sign_in` stays;
it is still how Android mints an ID token.

**Android** — the App Links intent filter host changes, and
`site/.well-known/assetlinks.json` is regenerated for the new host with the
same signing certificate fingerprints.

---

## Testing

The pgTAP suite is not decoration and is not dropped. It is ported, test for
test, to `vitest-pool-workers`, which runs real D1, KV and Durable Objects in
Miniflare and gives `runInDurableObject` and `runDurableObjectAlarm`.

| Today | Becomes |
|---|---|
| `01_schema_and_invariant` | DO unit: unbalanced entry refused; no hard delete; `clientKey` idempotency; `seq` monotonic; DO schema migration v1→v3 |
| `02_rls_and_invites` | Worker integration: stranger cannot read or write a group; invite spent exactly once; expired and revoked tokens; claiming sets one column |
| `03_push_tokens` | token ownership; recipients exclude the actor and non-members |
| `04_adversarial` | a member cannot rewrite another's `upi_vpa`, blank a `profile_id`, remove an unsettled member, rewrite `created_by`, re-identify a group, or write an entry into a group they are not in |
| `05_fx` | conversion, coverage, backfill throttling, concurrent backfill and cron |
| `06_activity` | no event when nothing changed; one event for one multi-row save; actor attribution; no client write path |
| `07_account_deletion` | placeholders retained with names; co-members' balances unchanged; groups nobody can read are deleted |

Plus, Dart side:

- `test/data/fake_remote_ledger.dart` updated to the new interface, so the
  existing sync and UI tests keep running with no backend.
- `test/data/cloudflare_integration_test.dart` replaces
  `supabase_integration_test.dart`: the real adapter against `wrangler dev`,
  skipping itself when nothing is listening, and required in CI. It is the only
  thing that catches a wrong route, a filter that does not mean what it looks
  like, or a rule that forbids something the app has to do.

Local development stops needing Docker: `npx wrangler dev` gives local D1, KV
and Durable Objects.

---

## CI/CD

GitHub Actions stays. Workers Builds cannot build the Flutter bundle, and the
bundle and the Worker deploy together as one artifact.

- `dart` — unchanged, plus the generated client is regenerated and the tree
  checked for drift, the way `drift_schemas/` already is. Needs a JDK, which
  the Android toolchain in `release` already pulls in.
- `worker` — `npm ci`, `biome check`, `tsc --noEmit`, `vitest run`,
  `wrangler deploy --dry-run`,
  and three drift checks with `git diff --exit-code`: `auth generate`,
  `drizzle-kit generate` for both schemas, and the emitted OpenAPI document
  against the committed `docs/openapi.json`. A wire change that skips the spec
  fails here rather than in the client.
- `audit` — `npm audit --omit=dev`. Dev-only findings are not a gate: the test
  pool's Miniflare pulls in `sharp` for local image emulation, and the only
  "fix" is a major downgrade of the pool.
- `integration` — `wrangler dev` in the background, then the Dart adapter test.
- `build` — the web bundle, as now.
- release — build web, then `cloudflare/wrangler-action` deploys Worker and
  assets in one step, then the signed Android bundle.

The `database` job (`supabase start` / `supabase test db`) and the Deno checks
in `tooling` are deleted. Secrets needed: `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`.

---

## Phases

Each phase ends green — analyzer clean, tests passing, nothing half-migrated.
Supabase keeps running untouched until phase 7 deletes it.

**0 — Scaffold.** `server/` via C3, D1 and KV created by CLI, `wrangler.jsonc`,
Hono skeleton, vitest wired, `worker` CI job. Exit: `wrangler dev` answers a
health check and CI runs the empty suite.

**1 — Auth.** Better Auth on D1, its schema generated and committed, the three
identity endpoints, Resend sender, `profiles` hook, bearer tokens. Dart
`BetterAuthService` replaces `SupabaseAuthService`. Exit: every branch of
link-or-sign-in covered by vitest; sign-in, guest, link, and the
already-claimed refusal all work end to end on a device.

**2 — The Group DO.** Schema, migration runner, `putGroup`, `putMember`,
`upsertEntry`, `deleteEntry`, events, every guard, `changesSince`. All seven
pgTAP files ported and passing. **This phase is the gate**: no client work
starts until the adversarial suite is green.

**3 — Client sync.** The Dart client is generated from `docs/openapi.json` by
`openapi_generator` and replaces `wire.dart`; `mappers.dart` keeps translating
its DTOs into the freezed domain models, so nothing above `data/` changes shape.
`RemoteLedgerApi` reshaped around one feed per group and an `int` cursor, Drift
schema bump and regenerated contracts, `fake_remote_ledger` updated. Exit: the
browser sync suite and `sync_test.dart` pass against the fake, and the
integration test passes against `wrangler dev`.

**4 — Invites, profiles, devices, deletion.** `link_tokens`, both link kinds,
placeholder claiming, the profile feed, device registration, account deletion.

**5 — FX, reference data, push.** `Fx` DO, providers ported, KV month blobs,
cron triggers, bundled currencies and categories, FCM from the DO with a KV
token cache.

**6 — Serving.** Static assets in `wrangler.jsonc`, `_headers` with COOP/COEP,
custom domain, `assetlinks.json` and the App Links filter on the new host,
Google OAuth redirect URIs, `tool/build_web.dart` retargeted. Exit: the whole
product served from `opensplit.eigeninteractive.com`.

**7 — Removal.** Delete `supabase/`, `firebase.json`, `.firebaserc`, the
Supabase CI jobs and `supabase_flutter`. Rewrite the README's backend half,
replace `docs/cloudflare-architecture.md` with what actually runs, rewrite
PRINCIPLES.md #6 and the three places that echo it (see *The promise that does
not survive*), and update the store listing URLs.

### How this runs

Straight through, phases 0 to 7, each left green, with a report at the end.

Every phase is built and verified locally: `wrangler dev` serves local D1, KV
and Durable Objects, and `vitest-pool-workers` runs the suites against the same
Miniflare. Nothing in this work authenticates to or mutates the Cloudflare
account. The commands that do — creating the D1 database and KV namespace,
setting secrets, attaching the custom domain, registering the Google OAuth
redirect URI, updating the Play Console URLs — are collected in
`docs/cloudflare-runbook.md` for you to run, in order, with what each one
expects to print.

The consequence worth stating: account-level problems — a domain not attached,
a secret not set, an OAuth redirect URI not registered — cannot surface until
you run the runbook. Phase 6 is written to fail loudly on each of them rather
than to half-work.

---

## The promise that does not survive

PRINCIPLES.md #6 says self-hosting is a first-class path, that `docker compose
up` gives a working instance in under fifteen minutes, and that every release
is tested against a self-hosted instance. Today that is true: the self-host
path is `supabase start`, which is the same local stack CI uses.

After this migration it is false. Durable Objects, D1 and KV are not
open-source products. `workerd` runs Durable Objects and Miniflare simulates D1
and KV, but Miniflare is a development simulator and nobody should run a
household's financial records on one. There is no honest fifteen-minute path,
and there will not be one.

The file opens with "These are commitments, not aspirations. They are published
here so that they can be held against us", so it is rewritten rather than left
to rot. No portability seam is built and none is pretended: the Durable Object
is written in the shape the platform wants.

Phase 7 replaces #6 with something true. Proposed text, to be edited before it
ships:

> ### 6. Your records are portable, even though the server is not
>
> The backend is deliberately thin — it stores rows and enforces one
> invariant, and computes nothing. The client reaches it through one Dart
> interface over a documented HTTP API, so pointing it somewhere else is a
> matter of writing that one class.
>
> But the hosted backend runs on Cloudflare Durable Objects, D1 and KV, which
> are not products you can stand up yourself. There is no supported self-host
> path, and we are not going to imply one. What survives is the part that
> actually protects you: your ledger lives on your device in plain SQLite,
> exports to CSV, and works with no server at all — see #7 — and AGPL-3.0
> still obliges any hosted fork to publish its changes.

The same correction is due in three other places, all in phase 7:

- the README's "Self-hostable for real" bullet, and its "Requires the Flutter
  SDK, Docker, and the Supabase CLI" line, which becomes Node and Wrangler,
  with no Docker at all;
- the doc comment on `RemoteLedgerApi`, which currently calls itself "what
  makes the self-hosting promise real rather than aspirational". The second
  half of that sentence — "what provides an exit if the hosted backend's terms
  change" — is still true and stays;
- `docs/cloudflare-architecture.md`, whose closing section is written as though
  self-hosting were still a constraint on the design.

Nothing else in PRINCIPLES.md is affected. #1, #2, #3 and #5 are about what the
product charges for and watches, and #7 — the app surviving this project being
abandoned — is if anything strengthened, since the device holds the whole
journal and computes every number itself.

## Risks

- **10 ms CPU on Workers Free.** Page sizes are capped and JSON building is kept
  cheap, but a large first sync is the thing to measure. Mitigation is a $5
  plan, not a redesign.
- **Better Auth moves fast.** Versions are pinned exactly and installed with
  `npm ci`; the generated schema is committed, so an upgrade shows up as a diff
  rather than as a surprise at runtime.
- **DO schema migrations are lazy and per-object.** A group not touched for six
  months migrates on its next open. The migration runner needs a test that
  opens a v1 object with v3 code.
- **The D1 index can drift from the DOs.** Outbox plus alarm plus a weekly
  reconciliation, and the DO always re-checks, so drift costs a retry rather
  than an answer.
- **Losing the adversarial coverage in the gap.** Phase 2 does not finish until
  all seven suites are ported. This is the risk that actually matters: those
  tests encode a security model that took real incidents to write down.
- **The CDN in front of the service worker.** Cloudflare will cache and serve a
  stale bundle if the `no-cache` rules on `index.html`, `sw.js`,
  `flutter_bootstrap.js` and `manifest.json` are not ported from `firebase.json`
  to `_headers` exactly. The symptom is every user pinned to an old build, which
  a local-first app hides well and for a long time. Phase 6 does not pass until
  a deploy is observed replacing a running client.
- **The domain move.** Free today because nothing is published. Every web user
  added before it happens makes it more expensive, because the local-first
  database and any guest session token are keyed to the origin.
