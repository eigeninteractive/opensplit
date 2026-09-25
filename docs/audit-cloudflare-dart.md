# Audit: Cloudflare backend ↔ Dart client — types, layers, simplicity

Working notes. Started 2026-09-25 against `cloudflare` @ e7376f6. Status:
**audit complete; refactor done in the working tree (uncommitted), see §7.**

Scope: the Worker's wire types (Drizzle → Zod → OpenAPI), the generated
`packages/opensplit_api`, and every Dart layer that re-describes those types
(`lib/data/sync`, `lib/data/local`, `lib/data/repositories`,
`lib/domain/models`, `lib/domain/repositories`, `lib/application`).
Not in scope: presentation widgets, balance/split maths, FX provider logic.

---

## 1. What the product wants (the yardstick)

- **Local-first.** The device holds the ledger in SQLite (Drift) and computes
  every number. The server stores rows and enforces one invariant.
- **One Durable Object per group**, sole writer → one monotonic `seq` per group
  → one cursor per group, whole-change pages.
- **One wire contract.** Zod (`server/src/schemas`) → `docs/openapi.json`
  (committed, CI drift check) → dart-dio + json_serializable client
  (committed, CI drift check). The Zod file header says it outright: *"There is
  no second place the wire format is described."*
- PRINCIPLES #6: *"The client reaches the server through a single interface
  over a published OpenAPI contract, so a fork points at a different server by
  writing one class."*

The server half of that holds up well. The Dart half does not: the generated
client is consumed only by hand-written adapters that translate every wire type
into a second, hand-written copy of itself, and then into a third (Drift).

---

## 2. Inventory: how many times is each concept written down?

Counting hand-maintained descriptions only (generated code excluded).

| Concept | Where it is described by hand | Count |
|---|---|---|
| **Entry** | Drizzle `entries`/`entry_payers`/`entry_shares` · Zod `EntrySchema` + `EntryInputSchema` + `PayerSchema` + `ShareSchema` · Dart `Entry`/`EntryPayer`/`EntryShare` (freezed) · Drift `Entries`/`EntryPayers`/`EntryShares` · `entry_json.dart` codec · 3 hand mappers (api→domain, domain→api, Drift row→domain) + `writeEntryInTransaction` (domain→Drift) | 5 shapes, 5 mappings |
| **Entry snapshot** (event payload) | Zod `EntrySnapshotSchema` + `MoneyRowSchema` · TS `snapshotOf` · Dart `EntrySnapshot`/`MemberAmount` (freezed) · `snapshotFromPayload` + `snapshotPayload` hand codec · `snapshotOf` (Dart) | 3 shapes, 3 codecs |
| **EntryKind / SplitKind** | Drizzle `text({enum})` · Zod `z.enum` · Dart domain `enum` · 4 hand switch-mappers in `cloudflare_ledger_api.dart` · 2 by-name fallbacks (`_enumOr`, `_enumByName`) | 3 lists, 6 mappers |
| **EventKind** | Drizzle `text({enum})` · Zod `EventKindSchema` · Dart `GroupEventKind` + hand `wireName` table + hand `parse` (duplicating the generated `api.EventKind`, which already has `unknownDefaultOpenApi`) | 3 lists + 1 wire table |
| **Group / Member / Profile** | Drizzle · Zod · freezed domain · Drift · mappers api→domain, domain→api, Drift→domain (Profile's twice: `mappers.dart` and `DriftProfileRepository._toDomain`), domain→Drift in `apply_changes` | 4 shapes, 4–5 mappings each |
| **Currency / Category** | JSON bundle · Zod · freezed domain · Drift · 2 mappers | 4 |
| **Bootstrap / ChangePage / ProfilePage / Reference / FxRate** | Zod · then re-declared by hand in `remote_ledger_api.dart` as `RemoteBootstrap`, `GroupChanges`, `ProfilePage`, `ReferenceData`, `RemoteFxRate` | 2 each |
| **Invite / GroupLink / Placeholder / LinkPreview** | Zod · `InviteLink`, `GroupLink` (name-clashes with `api.GroupLink`), `LinkPlaceholder`, `InvitePreview`, `GroupLinkPreview` in `domain/repositories/invite_api.dart` | 2 each |
| **Account / EmailFlow / IdentityOutcome** | Zod · `Account`, `EmailFlow`, `SessionKept`/`SessionReplaced` in `auth_service.dart` | 2 each |
| **Error envelope `{error:{code,message,retry}}`** | Zod `ErrorSchema` (+ a second inline copy in `api/reference.ts` → generated `GetFxRates400Response`) · parsed by hand from `Map` in **three** Dart places (`CloudflareLedgerApi._guard`, `CloudflareInviteApi._guard`, `BetterAuthService._codeIn/_messageIn`) into **two** exception types (`RemoteRejected`, `InviteRejected`) · `Retry` re-declared as `RejectionKind` | 2 schemas, 3 parsers |
| **Calendar date `YYYY-MM-DD`** | 6 hand-rolled `padLeft` formatters (`sync_engine`, `cloudflare_ledger_api`, `entry_snapshot`, `snapshot_diff`, `drift_fx_repository` (UTC!), `entry_editor_screen`) | 6 |

The generated `api.*` types are never seen outside four adapter files. They are
decoded, copied field-by-field into look-alikes, and dropped.

---

## 3. Findings

Severity: **H** wrong data on a device · **M** structural cost / latent bug ·
**L** tidy-up. "CONFIRMED" = reproduced or verified in code, not inferred.

### Correctness

#### F1 [H, CONFIRMED] A skipped remote row is never re-delivered → permanent divergence

`apply_changes.dart` skips any row whose id is in the outbox (`_dirtyIds`) but
still advances the group cursor past it. Nothing re-fetches it later.

Repro (throwaway test on `sync_test.dart`'s `divergent()` helper, since
deleted): B changes an expense to 450 and syncs; A edits it to 600 offline; A's
push fails transiently — `_syncGroup` still runs the pull after a failed push —
so the pull skips the server's 450 row as dirty and advances the cursor. Next
sync, A's push is refused `stale` → parked in `entry_conflicts`, outbox item
completed → pull from the advanced cursor returns nothing.

Observed: `A local amount: 60000`, conflict notice `current: 60000`. A shows
600 forever, the group shows 450, and the conflict screen compares the edit
with itself.

Same shape for **dead letters**: they stay in `outbox`, so `_dirtyIds`
includes them forever and that row never receives a remote update again.

`_parkConflict`'s doc says *"the row's version marker is wound back to the base
… which is what lets the pull immediately afterwards apply the server's
version"* — no code does that (a leftover from the timestamp design). The
existing happy-path test only passes because push happens to precede pull in
the same run.

Direction: on `stale`, rewind the group cursor to `min(cursor, baseSeq)` (or
have the 409 body carry the current `Entry` and apply it). Stop discarding
the push response: it *is* the server's row, but today only its `seq` is kept.

#### F2 [M, CONFIRMED] The feed's total order is built end-to-end and then not used

The server has a unique `(seq, ordinal)` index with a long rationale, `ordinal`
is on the wire, and Drift has the column. `DriftActivityRepository.watchGroup`
orders by `createdAt desc, id desc`. Two lines from one change share
`createdAt`, so they tie-break on a random UUID — exactly the "archived above
renamed" bug `ordinal` was added to prevent. `grep ordinal lib/` finds only
plumbing, no `orderBy`. The "provisional rows sort after confirmed ones" rule
in `GroupEventRow`'s doc isn't implemented either.

#### F3 [M, CONFIRMED] A calendar date is a `DateTime` under two conventions

`entryDate` is `YYYY-MM-DD` on the wire (correctly a string), but in Dart it's a
`DateTime`: **local midnight** when it comes from the server
(`DateTime.parse('2026-09-23')` in `_entry`), **UTC midnight** when created on
the device (`DateTime.utc(...)` in `entry_draft.dart` and the editor). Drift
stores both as text, so the difference survives.

Code that is correct for one convention is wrong for the other:
`isoDate()` in `drift_fx_repository.dart` and `_oldestRateNeeded` both call
`.toUtc()` first. For a server-origin entry east of UTC (India, the main
market) that turns 23 Sep into 22 Sep. Today the editor normalises before
calling `quote`, so the visible damage is limited to the backfill window
reaching one day too far. But it's a trap: one caller away from a wrong rate.
There are also six hand-written `YYYY-MM-DD` formatters (inventory above) and
`entry_snapshot.dart` has a paragraph warning about exactly this.

Direction: one representation. Either a tiny `extension type CalendarDate(String)`
(the wire already uses the string) stored as TEXT in Drift, or `DateTime`
always UTC midnight with one `parse`/`format` pair. Delete the six formatters.

#### F4 [L] Stale-conflict screen and dead letters read the local row as "current"

Follows from F1: `PendingConflict.current` is the local `entries` row, which
by F1 can be this device's own rejected edit. Fixing F1 fixes this.

### Type flow / duplication (the main ask)

#### F5 [H, structural] The generated client is wrapped in a hand-written copy of itself

`RemoteLedgerApi` (data/sync) declares `RemoteBootstrap`, `GroupChanges`,
`ProfilePage`, `ReferenceData`, `RemoteFxRate`, `RejectionKind` — field-for-field
copies of `api.Bootstrap`, `api.ChangePage`, `api.ProfilePage`, `api.Reference`,
`api.FxRate`, `api.Retry`. `CloudflareLedgerApi` (500 lines) converts between
them; most of it is `foo: row.foo`. `InviteApi` / `AuthService` /
`DeviceTokenRepository` do the same for their endpoints.

The file's stated reason — *"this file is where a change to the contract shows
up as a compile error"* — works against itself. Code that used `api.Entry`
directly would get that compile error at the real use site. The adapter
*absorbs* contract changes: a new wire field silently goes nowhere because
nobody added it to the copy (e.g. `Profile.deletedAt`, `Invite.superseded`,
`LinkRevocation.revoked` are dropped today).

Where the copies really do add something, it's small enough to live elsewhere:
- `groupId` on `Member`/`Entry` → one extra argument when writing to Drift.
- The sealed `LinkTarget` split of `LinkPreview` → a 10-line extension on
  `api.LinkPreview`, not a parallel type family.
- `source_` → one field access.

#### F6 [H, structural] Inbound sync goes wire → domain → Drift; the middle step does nothing

`pullChanges` maps `api.ChangePage` into freezed `Group`/`Member`/`Entry`/
`GroupEventRow`, and `apply_changes.dart` immediately maps those into Drift
companions. Outbound, `_pushOne` reads Drift rows, maps them to domain, and
`CloudflareLedgerApi` maps domain to `api.EntryInput`. The domain objects are
built and thrown away in both directions. Mapping `api.*` ↔ Drift companions
directly takes out a whole layer of mappers along with the `RemoteLedgerApi`
DTOs.

#### F7 [M] Four domain models duplicate Drift's own row classes

`Group`, `Member`, `Profile`, `Currency`, `Category` (freezed) have the same
fields as Drift's generated `GroupRow`, `MemberRow`, `ProfileRow`,
`CurrencyRow`, `CategoryRow`, which are already immutable and come with
`copyWith`/`==`. `mappers.dart` exists only to copy one into the other. The
getters on the freezed classes (`isArchived`, `isPlaceholder`, `isActive`,
`minorPerMajor`, `formatPlain`, …) can be extensions on the row classes. (Drift
can also be told to use your own class via `@UseRowClass` if you'd rather keep
the name `Group`.)

`Entry` is the only real aggregate (row + payers + shares) and reasonably stays
its own type. Even so, `EntryPayer`/`EntryShare` duplicate `api.Payer`/`api.Share`
and `MemberAmount` duplicates the unemitted `MoneyRow`.

#### F8 [M] Event payloads are hand-parsed because the contract lies about emitting them

`schemas/ledger.ts` says the four payload schemas *"are still registered as
named schemas above, so the contract documents them even though `payload` does
not point at them."* They aren't: `docs/openapi.json` has no `EntrySnapshot`,
`MemberEventPayload`, `GroupEventPayload`, `LinkEventPayload` or `MoneyRow`
(an unreferenced `.openapi("Name")` isn't emitted). So Dart hand-codes
`snapshotFromPayload`/`snapshotPayload`, `GroupEventRow.name`/`previousName`,
and `_amounts`, with their own enum fallbacks.

Fix: register them explicitly (`app.openAPIRegistry.register("EntrySnapshot",
EntrySnapshotSchema)` etc.). The generator then emits `api.EntrySnapshot`,
with `fromJson` for the pull side and `toJson` for writing provisional rows,
so one codec replaces three. Keep `payload` itself as a free-form object, since
the `oneOf` limitation is real.

#### F9 [M] Enums are declared three times and mapped by hand six times

`EntryKind`, `SplitKind`, `EventKind`: Drizzle `text({enum:[…]})` and
`z.enum([…])` use separate literal lists on the server; Dart has its own
enums plus switch-mappers both ways plus `GroupEventKind.wireName`/`parse`,
which re-implements the generated `api.EventKind` (it already has
`unknownDefaultOpenApi` — that's the documented reason dart-dio was picked).

Server: declare each list once (`export const entryKinds = [...] as const`) and
use it in both Drizzle and Zod. Client: use `api.EntryKind`/`api.SplitKind`/
`api.EventKind` directly. Drift can store them with `textEnum<api.EntryKind>()`
or a 5-line `TypeConverter` that maps unknown values to the sentinel, which
keeps the forward-compat property the comments care about.

#### F10 [M] One error envelope, three hand parsers, two exception types, and an untyped `code`

- `ErrorSchema.code` is `z.string()`, but the server has a closed list
  (`refusalCodes` in `refusal.ts`). Make it `z.enum(refusalCodes)` (plus the
  worker-level codes such as `no_session`, `bad_request`, `not_found`,
  `internal`) so Dart gets an enum with an unknown sentinel.
- `api/reference.ts` declares the envelope inline twice → generated
  `GetFxRates400Response` + `GetFxRates400ResponseError` duplicates.
- Dart parses `body['error']['code'|'message'|'retry']` out of a raw `Map` in
  three files instead of `api.Error.fromJson`. `RemoteRejected` and
  `InviteRejected` wrap the same envelope; `InviteRejected` throws away `code`
  and `retry`, and the UI shows the server's English message verbatim, which
  sidesteps the app's l10n.
- `RejectionKind` duplicates `api.Retry`.

Direction: one `ApiFailure` built once from `DioException` via
`api.Error.fromJson`, carrying `api.ErrorCode` + `api.Retry`. Screens map
codes to localised copy.

#### F11 [L] Server-internal bookkeeping leaks onto the wire

`Invite.superseded` (→ `InviteSupersededInner` in Dart) and
`MintedLink.superseded` exist *"because the derived index in D1 has to forget
them too"*. That's the Worker's job between the DO and D1, not the client's.
Nothing in Dart reads them. Return them from the DO's RPC, but not in the HTTP
schema.

#### F12 [L] Zod response schemas aren't derived from Drizzle

`MemberSchema`, `GroupSchema` (≈ `meta`), the entry columns, `InviteSchema`,
`EventSchema` repeat Drizzle's columns by hand; `changesSince` then returns
raw Drizzle rows as the Zod type, and nothing checks they still match
(responses aren't validated). `drizzle-zod`'s `createSelectSchema(members)`
(or `drizzle-orm/zod` in newer Drizzle) derives them, with `.pick/.omit/.extend`
for the few wire-only differences, and `.openapi("Member")` on the result.
Worth doing for the flat row types; the nested `Entry` (with payers/shares)
stays an `extend`.

### Architecture / simplicity

#### F13 [M] Interfaces with one implementation and no fake

`InviteApi`, `DeviceTokenRepository` and `AuthService` each have exactly one
production implementation. `InviteApi` and `DeviceTokenRepository` have **no**
test fake (only the real-Worker integration test uses them). `AuthService` has
fakes in 3 presentation tests. So `InviteApi` and `DeviceTokenRepository` are
pure indirection. `RemoteLedgerApi` is different — see Q2.

Layering is also inconsistent: `RemoteLedgerApi` lives in `data/sync/`,
`InviteApi` in `domain/repositories/`, and both import concrete domain models.

#### F14 [M] A 604-line Dart re-implementation of the Durable Object

`test/data/fake_remote_ledger.dart` re-implements seq allocation, paging, the
balance invariant and stale-base rules. That's a third implementation of the
server's semantics (TS, Dart fake, and the Dart client's assumptions), and it
can drift from the real one silently. It's the main reason `RemoteLedgerApi`
exists. `cloudflare_integration_test.dart` already runs the real client
against a real local Worker. See Q2.

#### F15 [L] Thin wrappers and one-arg variants

- `InviteApi.peek` = `peekLink` + type test; `redeem` = `joinWithLink` with no
  args. Two methods doing one thing.
- `BearerAuthInterceptor` is generated (`lib/src/auth`) but unused. It isn't
  wired because the spec declares no `securitySchemes`. Declaring
  `bearerAuth` (and `cookieAuth`) in the spec would document the API's auth
  *and* replace the hand interceptor in `api_client.dart`.
- `_IsoDatesInQueryStrings` interceptor patches a generator quirk for
  `DateTime` query params. Only `getProfiles(since)` uses one; declaring it as
  a string would make the interceptor unnecessary, and then nothing needs
  patching.

#### F16 [L] `FeedCursors` misused as a key-value store for the FX floor

`_writeFxFloor` stores a date as a fake `DateTime` in `cursor` **and** as a
string in `cursorId`, under feed name `'fx:floor'`, in a table documented as
"a `(timestamp, id)` keyset cursor". Only one real timestamp feed is left
(profiles). One small `sync_state(key, value)` table, or a column, says what it
is.

#### F17 [L] Outbox operation is a string matched three ways

`Outbox.operation` is `text`, compared against `OutboxTarget.name`, parsed with
`values.byName`, and ranked by string literal in `_pushOrder`
(`'group' => 0, 'member' => 1, _ => 2`). `textEnum<OutboxTarget>()` plus an
exhaustive `switch` on the enum would let the compiler check all of it.

### Documentation debt

#### F18 [M] Comments describe the system that was removed, not the one that exists

Roughly 25–40% of lines in the audited files are comments (`lib/data/sync`
761/2983, `tables.dart` 257/517, `server/src/do/group` 999/2487), and 129 of
them mention removed mechanisms (`updated_at` LWW, triggers, RLS policies,
`auth.uid()`, `PT409`, SQLSTATE, `numeric(24,6)`, "the old backend", "phase 5",
`EntryFeed`, `[_drainProfiles]`). Several aren't just historical but **wrong
now**, and F1 and F8 are bugs that a wrong comment hid:

- `SyncEngine` class doc: "cursor over `(updated_at, id)`", "server stamps
  `updated_at`, last-write-wins".
- `SyncEngine.push` doc: rows "carry a device clock in `updated_at` which
  `EntryFeed` compares" (neither exists).
- `_parkConflict`: "version marker is wound back" (it isn't — F1).
- `Entry` doc: "sync is a cursor over `updated_at`"; a leftover doc comment
  ("Version of the split algorithm…") for a field that no longer exists.
- `EntryConflicts.attempted`: "through the wire codec" vs `entry_json.dart`:
  "deliberately **not** the wire codec".
- `schemas/ledger.ts`: payload schemas "registered… so the contract documents
  them" (they aren't — F8).
- `EntryShares.weightMicros`: "matching `numeric(24,6)` on the server".

AGENTS.md asks for comments that explain *why*, not changelog prose. A rule
like "describe the current design; history goes in the commit message" would
cut these files by roughly a third and stop them drifting out of date.

---

## 4. Target shape (pending answers to §5)

```
server/src/db/*/schema.ts   Drizzle tables + `as const` enum lists  ← single source
server/src/schemas/*.ts     Zod = createSelectSchema(table).pick/extend(...).openapi(Name)
                            + explicit registry for payload + error-code schemas
docs/openapi.json           generated (unchanged)
packages/opensplit_api      generated (unchanged) — now incl. EntrySnapshot, ErrorCode
lib/data/remote/            SyncApi-sized glue only:
                              ApiFailure.fromDio(e) (one place)
                              api.* ↔ Drift companion extensions (one file)
lib/data/local/             Drift tables; row classes ARE the read models;
                              Entry aggregate stays; enums = api enums via converter
lib/domain/                 pure logic (split, balance, fx, activity diff) over
                              Drift rows / Entry / api.EntrySnapshot
```

Deletes (roughly): `remote_ledger_api.dart` DTOs, most of
`cloudflare_ledger_api.dart`, `cloudflare_invite_api.dart`'s parallel types,
`mappers.dart`, `entry_json.dart`, the snapshot codec, freezed
`Group/Member/Profile/Currency/Category/MemberAmount`, `GroupEventKind`'s wire
table, `RejectionKind`, `InviteRejected`, 5 of 6 date formatters.

---

## 5. Open questions (these decide the target shape)

- **Q1. Domain models vs Drift rows.** Drop the freezed `Group/Member/Profile/
  Currency/Category` and use Drift row classes (with extensions) app-wide,
  keeping only `Entry` as an aggregate? Or keep a freezed domain layer and
  just remove the wire-side duplicates (F5/F6)?
- **Q2. The fake server.** Keep `FakeRemoteLedger` (fast, no Node needed, but a
  second copy of DO semantics) and so keep a `RemoteLedgerApi` seam? Or run the
  sync suite against a local `wrangler dev` like `cloudflare_integration_test`
  already does, and delete the seam and the fake? Middle option: keep a
  seam typed in `api.*` (no DTO copies) so the fake returns generated types.
- **Q3. PRINCIPLES #6 "a fork … by writing one class".** Is that a promise to
  keep in code? With the OpenAPI contract as the interface, a fork only needs
  to implement the contract and change `API_BASE_URL`. No Dart class is
  needed. If that's acceptable, the sentence and the seam can both go.
- **Q4. Server-authored English messages.** Keep showing
  `error.message` verbatim (not localisable), or switch screens to
  `code` → l10n string with the message as a fallback?
- **Q5. Conflict storage format.** `entry_json.dart` avoids the wire codec on
  purpose so a parked conflict survives a wire rename. Is that durability worth
  a fourth Entry codec, or is `api.EntryInput.toJson` fine given conflicts are
  short-lived and the generated decoder tolerates unknown keys?
- **Q6. Scope of change.** Fix F1–F3 first as separate small PRs, then do the
  type-flow refactor (F5–F10) as one staged migration? Or fold everything into
  the refactor?

---

## 6. Decisions (2026-09-25) and refactor plan

- Q1 → Drift row classes are the read models; freezed Group/Member/Profile/
  Currency/Category go. `Entry` stays as the aggregate.
- Q2 → Keep a sync seam, typed in `api.*` (no DTO copies). The fake returns
  generated types.
- Q3 → PRINCIPLES #6 reworded: the contract is the seam.
- Q4 → not done. `ApiFailure` carries the typed `api.ErrorCode`, but the
  screens around it are hard-coded English, so localising error codes alone
  would be half a job. Follow-up.
- Q5 (my default) → parked conflicts stored as `api.EntrySnapshot` JSON (it
  carries `deletedAt`, so a refused delete stays a delete; rows written by
  the old codec decode unchanged).
- Q6 → one refactor, done in stages. Each stage ends with both test suites
  green. Baseline: 437 Dart / 198 server tests.
- F12 (drizzle-zod) deferred: it needs a new dependency. Enum lists are shared
  as `as const` arrays instead.

Stages:
1. Server contract: shared enum lists; register payload schemas + `MoneyRow`;
   typed `ErrorCode`; one error schema everywhere; drop `superseded` from HTTP
   responses; regenerate spec + client.
2. One `ApiFailure` from `DioException` via `api.Error`; delete
   `RejectionKind`, `InviteRejected`, three hand parsers.
3. Sync seam in `api.*`; delete the `RemoteLedgerApi` DTOs; `apply_changes`
   maps `api.*` → Drift directly; push maps Drift → `api.EntryInput`.
4. Drift rows as models; delete freezed look-alikes and `mappers.dart`.
5. Generated enums everywhere (Drift converters with unknown sentinel).
6. `api.EntrySnapshot` replaces the hand snapshot codec; `entry_json.dart` goes.
7. One calendar-date type; delete the formatters.
8. Fix F1 and F2 with regression tests.
9. Comments/docs: remove the historical prose, reword PRINCIPLES #6, update
   architecture.md.

Progress log:

## 7. What was done

All of it was verified with: `dart analyze --fatal-infos` clean; 443 Dart tests
(was 437); Chrome + browser-DB suites; 32 integration tests against a real
local Worker (was 31); 198 server tests; biome; server typecheck; the
generated-client and Drift schema drift checks CI runs.

### New bug found while refactoring

**F19 [H, CONFIRMED] Restoring a group, rejoining, and clearing a UPI handle
never reached the server.** `GroupPatch.archivedAt`, `MemberPatch.upiVpa` and
`MemberPatch.leftAt` were optional + nullable, so the generated client dropped
a null (`includeIfNull: false`), and the server reads an absent field as
"leave it alone". Proven with `GroupPatch(archivedAt: null).toJson()` →
`{name, simplifyDebts}`. Fixed by making those three fields required-nullable
on the wire (the DO keeps a `Partial<>` API). Covered by `wire_test.dart` and
a live integration test.

### Findings, fixed

| # | Fix |
|---|---|
| F1 | A stale refusal rewinds the group cursor to the edit's base (`SyncEngine._parkConflict`), so the server's version is read again. Regression test: "converges even when a pull skipped the newer version first". |
| F2 | Feed ordered by `(seq, ordinal)`, unconfirmed lines first (`newestFirst`/`oldestFirst` in `database.dart`). Test in `wire_test.dart`. |
| F3 | One `calendar_date.dart` (`calendarDate`, `parseCalendarDate`) that never converts through a time zone; wire dates parse to UTC midnight. Six formatters → one. |
| F5/F6 | `RemoteLedgerApi` is now typed in `api.*` (its fake too); the five DTO copies, `CloudflareLedgerApi`'s 500 lines of mapping, and the wire → domain → Drift hop are gone. `sync/wire.dart` is the only mapping, `api.*` ↔ rows. |
| F7 | Drift row classes are the models (`Group`, `Member`, `Profile`, `Currency`, `Category`, `GroupEventRow`); the freezed look-alikes, `mappers.dart` and the freezed `GroupEventRow`/`EntryEvent`/`EntrySnapshot`/`MemberAmount` are deleted. Drift runs as `not_shared` so riverpod_generator can see the row classes (`build.yaml`). |
| F8 | Payload schemas registered; `api.EntrySnapshot` replaces the hand codec (and `entry_json.dart`). |
| F9 | Enum lists shared between Drizzle and Zod; the app uses `api.EntryKind/SplitKind/EventKind` (via `domain/models/kinds.dart`), stored with one `WireEnumConverter`, with no on-disk change. An unknown split kind makes an entry unsaveable instead of silently "equal". |
| F10 | `ErrorCode` enum on the wire; one inline duplicate removed; one `ApiFailure` built from `api.Error`; `RemoteRejected`, `RejectionKind`, `InviteRejected` and three hand parsers deleted. `bad_request` merged into `malformed`. |
| F11 | `superseded` kept inside the Durable Object; `MintedLink`/`InviteSupersededInner` gone from the wire. |
| F13 | `InviteApi` interface and its five parallel types replaced by one `Invites` class returning generated types. `Account`/`EmailFlow` are the generated ones. |
| F16 | Floor comparison now reads the stored date string, not a fake `DateTime` (same table; a schema change was not worth it). |
| F17 | `Outbox.operation` is `textEnum<OutboxTarget>`; push order is the enum order. |
| F18 | Comments rewritten in every file touched; references to removed Postgres/Supabase machinery removed from the sync and schema layers. PRINCIPLES #6 reworded (the contract is the seam); README layout updated. |

Also fixed along the way: `requestFxBackfill` claimed to swallow failures but
threw into an unawaited future (now `.ignore()`d).

### Deliberately not done

- **F12** (derive Zod from Drizzle): done in §8.
- **F15**: `securitySchemes` in the spec, and the `DateTime` query interceptor.
  Both are small and would change generated code; left as they are.
- **Q4**: localising error codes (see §6).
- **Dead letters** still block remote updates to their row until retried.
  That was the design already ("kept, not deleted"); worth a product decision.
  (Decided in §9: a Discard action.)
- **`Outbox.payload`** column is unused; removing it needs a migration. (Done in §8.)
- Comments outside the audited layers (presentation, scheduler) were not swept.

## 8. Second pass

Prompted by five questions: why `wire.dart` exists; whether required,
nullable and optional mean one thing everywhere; dates; whether riverpod,
freezed and drift are all needed; and which way Drizzle and Zod should derive.

### Required, nullable, optional: one rule

Before, the spec mixed four states across bodies: required, required-nullable,
optional-with-default (`EntryInput.kind`, `GroupCreate.isDirect`, …) and
optional-meaning-"leave it" (`GroupPatch.name`). The generated Dart client
cannot say "absent" as distinct from null, so every optional field was
three states on the server and two on the device. F19 was one instance.
Three more were found:

- `Event.payload` was optional in the spec (a bare `z.custom` accepts
  `undefined`), so the Dart field was nullable and `wire.dart` papered over it
  with `?? const {}`.
- `Share.weightMicros` was optional in *responses* because one schema served
  both directions with a default.
- `baseSeq` on delete/restore was documented optional though the server
  refuses without it (coercion turns `null` into 0, so the generator reads
  the schema as nullable).

The rule now, stated at the top of `schemas/ledger.ts`: **every body field is
required, and `.nullable()` is the only way to say "none".** Optional is only
for query parameters, where a default is ordinary HTTP. Consequences:

- `GroupPatch`/`MemberPatch` became `GroupUpdate`/`MemberUpdate` on `PUT`
  (every editable field, every time), matching `ProfileUpdate`. The app
  already sent every field, so behaviour is unchanged, including that two
  devices editing different fields of one group is last-writer-wins by row.
  The Durable Object keeps a `Partial<>` API internally, where TypeScript can
  tell absent from null.
- No `.default()` in any body schema. The generated Dart constructors now
  require every field, so forgetting one is a compile error, and the compiler
  flagged every `?? default` in the fake server as dead code.

### Drizzle → Zod

Drizzle is the source, through `drizzle-zod` (Drizzle's own package; built
into `drizzle-orm` from v1). Nothing derives Drizzle from Zod. Response rows
that are table rows are derived: `Group`, `Member`, `Entry` (plus payers and
shares), `Event`, `Invite`, `Profile`, `FxRate`. Overrides give a column its
wire type where SQLite has none (timestamps, dates, named enums) or state a
meaningful range (`seq` ≥ 0, positive amounts). Request bodies stay written
out: they are deliberately narrower than rows and carry the validation. IDs
and currency codes on responses lose their `example`/`pattern`, which were
only documentation there.

### Dates

- `DateSchema` is `z.iso.date()`, not a hand regex that accepted month 13.
- The generator maps `format: date` to `String` (`tool/openapi_dart.yaml`):
  as `DateTime`, json_serializable would parse local midnight and send a full
  timestamp, which the server now refuses.
- `calendar_date.dart` uses `intl`'s `DateFormat('yyyy-MM-dd', 'en_US')`,
  already a dependency. Dart has no date-only type, so the one convention
  stays: a day is a `DateTime` at UTC midnight.
- `entries.entry_date` is stored as `yyyy-MM-dd` text (a Drift
  `CalendarDateConverter`), like `fx_rates.as_of` and the server.
- Four more ad-hoc formatters removed (`_iso` in analytics, both exports, the
  export filename).

### Local schema (v5)

`Outbox.payload` removed; `operation` renamed `target` (it holds an
`OutboxTarget`); `revision` required rather than defaulting to `''`;
`entry_date` as above. `schemaVersion` 5, snapshot and helpers committed.

### Comments

Every comment narrating history ("this used to…", past bugs, removed
backends) was rewritten as the present-day reason or deleted: about 45 across
`lib/`, `server/src/`, `tool/`, and two in the README. `tool/verify_config.dart`
ended in a doc comment attached to nothing; removed.

### Kept, and why

- **`wire.dart`.** A local row is not a server row: it can exist before the
  server has seen it (nullable `seq`), one database holds every group
  (`groupId`), an expense is three tables, and a date is a `DateTime`. Using
  the generated classes as Drift row classes (`@UseRowClass`) fails on the
  first two. The header now says so.
- **Drift, Riverpod.** Core, not remnants: the local-first database (native
  and web), and the app's dependency injection across ~100 providers.
- **freezed.** Down to seven value types (`Entry`, `EntryPayer`,
  `EntryShare`, `FxQuote`, `MemberBalance`, `Transfer`, `FieldChange`).
  `Entry` needs deep equality and `copyWith`, which is what freezed is for;
  build_runner already runs for Drift and Riverpod, so it costs nothing extra.

### Verification

198 server tests, biome, typecheck; generated-client check; `dart format`;
`dart analyze --fatal-infos`; 475 Dart tests including 32 against a live
local Worker; Chrome (136 + 12) and browser-DB (3) suites.

## 9. Discarding a refused write

A write the server refuses outright (a "dead letter") stays in the outbox, and
while it is there the pull skips that row, so this device keeps showing its own
version and ignores everybody else's changes to it. The banner offered only
"Try again", so a refusal that would never succeed left the row stuck.

The banner now also offers **Discard**, behind a confirmation.
`SyncEngine.discardRefused` drops every dead letter and puts the server's
version back:

- A row the server has: its group's cursor is rewound to `seq - 1`, so the next
  pull delivers the row even when the server's copy has not moved since (a
  rewind to `seq` would not, and the regression test fails with it).
- A row the server never had: deleted, since it exists nowhere else. A local
  member that an expense still names is kept rather than breaking the expense.
- A profile: its local timestamp is cleared and the profile feed re-read, so
  the server's copy wins.
- Provisional feed lines for the discarded change are removed.

Tests: two in `sync_test.dart` ("discarding a refused write"), one widget test
in `unsynced_banner_test.dart`.

## 10. The outbox key

The outbox was keyed on a string built from two columns it also stored
(`"entry:<id>"`, via `OutboxQueue.idFor`). It is now keyed on
`(target, targetId)` directly. `complete`, `fail` and `isCurrent` take the
row they were handed, and always match its revision too, so a response for an
older edit can never complete or back off a newer one. Before, that check was
optional (`revision: null` matched anything). `fail` also lost a redundant
second read. Local schema v6: v5 was already pushed, so it was bumped rather
than re-dumped.
