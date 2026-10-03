# The backend

One Worker on one origin serves the static site, the Flutter client and the
API. Behind it: one Durable Object per group, a single Durable Object for
exchange rates, a D1 database for the handful of facts that are genuinely
cross-group, and a KV namespace for things that are derived and rebuildable.

`docs/runbook.md` is how to stand it up; `docs/resetting-the-backend.md` is how
to tear it down and start again.

---

## The decision the whole design turns on

Not "which database" but **where the authorization boundary lives**. The answer
is: one Durable Object per group, which is that group's only writer.

Everything else follows. A Durable Object processes one request at a time and
owns exactly one group's rows, so the three hardest rules in the product are
ordinary code:

- **"Are you a member?"** is reading my own `members` table. No cross-table
  lookup, no recursion to design around.
- **"You may change this column, but only on your own row"** is a function with
  the old and new rows in hand.
- **`sum(payers) = sum(shares) = amount`** is an `if` inside the write, checked
  against every row the same change touches, before any of them commit.

Each of those is awkward wherever the check and the data live apart: the first
needs a lookup across groups, the second needs both the old and new values, and
the third cannot be judged until every row the change touches has arrived. Here
they are three functions in the object that owns the rows.

---

## The sequence number

Because the object is a group's only writer, it can hand out a strictly
increasing integer. Every row written by one change shares one `seq`, and a page
of changes is only ever cut between sequence numbers — so a device sees a whole
change or none of it, and can never hold an expense whose shares have not
arrived.

One feed uses a timestamp cursor instead, and honestly: profiles live in D1, which
several requests write concurrently, so there is nothing there that can issue a
sequence number. A time cursor cannot see a profile that becomes *visible*
without changing — somebody named long ago claiming a place in your group — so
each group page carries the profiles of its current members, read by the ids
the page itself names. The profile feed then only has renames to deliver.

---

## What each store holds

**The group object** (`server/src/db/group/schema.ts`) — `members`, `entries`,
`entry_payers`, `entry_shares`, `events`, `invites`, `group_link`, plus four
tables that exist because the object is a little machine as well as a table:
`counter` (the sequence allocator), `meta` (the group row itself), `tombstone`
(what is left after a purge, so a device that still holds a copy is told to drop
it rather than being refused forever), `outbox` (writes owed to D1) and
`schedule` (the dormancy alarm).

A purge happens when a group is archived, settled in every currency and quiet
for a year, or at once when its last account holder deletes their account.
Dropping it on the device is not a soft delete: `applyGroupChanges` deletes the
local group row and the foreign keys cascade to its members, expenses, payers,
shares and activity. An edit that device never pushed goes with it. The copy
that survives is whatever somebody exported beforehand.

**D1** (`server/src/db/d1/schema.ts`) — `profiles`, `memberships`,
`device_tokens`, `link_tokens`, plus Better Auth's own four tables. Everything
here except `profiles` is a **derived index**: the objects are the truth, and D1
is what makes "which groups am I in" and "what does this token point at"
answerable without asking every object in the account.

The index is kept by rules, not by a repair job. Each object stages its index
writes in `outbox` in the same transaction as the change, and sends them in
order, one flush at a time, until D1 has taken every one; a failure is retried
by the object's alarm. The outbox row's id travels as `memberships.version`, so
a copy that arrives late never replaces a newer one, and `purged_groups` stops
any write reaching D1 for a group already collected. `link_tokens` is
insert-only: a token never moves between groups, and whether it still works is
the object's call.

D1 refuses a membership for an account whose `user` row is gone, and the object
then turns that member into a placeholder itself. That is what makes account
deletion complete without depending on timing: it deletes the `user` row first,
so every membership D1 will ever hold for the account is already there when it
reads them, and each group's row is removed only once that group has forgotten
the account. Rows left for an account that no longer exists are a deletion that
was interrupted, and the daily sweep finishes it.

**The rate object** (`server/src/db/fx/schema.ts`) — `fx_rates`,
`provider_health`, `backfill_requests`. A singleton, and that is deliberate: KV
is last-write-wins, so a daily run and an on-demand backfill rebuilding the same
month from two different reads would silently drop whichever landed first. One
writer removes the race rather than detecting it.

**KV** (`CACHE`) — one blob per month of rates, and the FCM access token. Both
are derived from something else and wrong only until the next write. The object
writes; the edge serves.

**The Worker bundle** — currencies and categories, as JSON files compiled into
the script. They are a few dozen rows that change about never and that a device
cannot create a group without. A table would have been a migration and a read
for data that ships with the code anyway.

---

## The contract, and how types reach the app

Each shape is declared once and derived from there:

```
Drizzle tables ──drizzle-orm/zod──▶ Zod rows, and request bodies picked from them
    ──@hono/zod-openapi──▶ docs/openapi.json
    ──openapi-generator (dart-dio)──▶ packages/opensplit_api
    ──lib/data/sync/wire.dart──▶ Drift rows
```

- **Rows are their tables.** `createSelectSchema(table, refine)` derives each
  row; the refinements give a column its wire type where SQLite has none (a
  timestamp, a date, a named enum, a length or a regex). Refinements are
  functions, so Drizzle still applies each column's own nullability.
- **Request bodies are `.pick()`s of those rows**, so a column's type and its
  validation are stated once for both directions. `EntryInput` picks the
  entry's editable columns from one list (`editableEntryColumns`), which the
  group object also uses to decide whether a save changed anything.
- **Closed vocabularies** (entry, split, event and link kinds, platforms,
  outbox kinds, chores) are one `as const` list each, used by the column, the
  Zod enum and so the Dart enum. An unknown value decodes to the generator's
  `unknownDefaultOpenApi`.
- **An event carries its payload in a typed field per shape** — `entry`,
  `member`, `group`, `link`, exactly one set, chosen by `kind` — rather than one
  untyped `payload`. The generator cannot read `oneOf`; separate nullable
  fields give the app a generated class for each without it. The object stores
  them the same way, so the table *is* the wire row.
- **The push message is a contract type** (`PushData`), registered as a
  component though no route returns it, and parsed on the device with the
  generated class.
- **Every session operation is an `/api/identity/*` route** returning contract
  types (`Session`, `IdentityOutcome`, `GoogleRedirect`), each calling Better
  Auth's server API. Better Auth's own HTTP handler is mounted only for the
  OAuth callback Google redirects to. Its `openAPI()` plugin emits 3.1 with
  loose schemas, and merging it would put those in the app.
- **Security is declared** (`bearer`, `cookie`), so the generated client's own
  bearer interceptor attaches the Android token; the app sets it with
  `setBearerAuth` when the session changes.
- **The app uses the generated types directly.** `wire.dart` is the only
  translation, because a local row is not a server row: it can exist before
  the server has seen it (null `seq`), it carries the `groupId` a page states
  once, an expense is three tables, a date is a `DateTime`, and an instant
  leaves as UTC.
- CI regenerates the contract and the client (`dart run
  tool/generate_api_client.dart --check`) and fails on any difference.
- **There is no fake server.** The app's sync, session and client tests run
  against a local `wrangler dev` (`flutter test --tags integration`), so the
  rules they exercise are the server's own.

A generator quirk worth knowing: a named component first reached through
`.nullable()` is emitted nullable everywhere. `app.ts` registers the ones held
as nullable before any route uses them.

### Required, nullable, optional

**Every body field is required, and `null` is the only way to say "none".** A
generated Dart client cannot send "absent" as distinct from null (it drops a
null optional field), so an optional field would have three states on the
server and two on the device. Every write is therefore a `PUT` of the whole
row at the id the device minted — `PUT /groups/{g}`, `/members/{m}`,
`/entries/{e}` — which creates it or replaces it, so a retry is the same
request. Soft deletion is a field of that row (`deletedAt` set or null; the
server stamps its own time), not a separate verb. Optional exists only for
query parameters, where a server default is ordinary HTTP.

### Dates

An instant (`createdAt`, `deletedAt`, …) is an ISO 8601 timestamp, UTC, from the
server's clock. An expense's date is a **calendar day**, not an instant:
`YYYY-MM-DD` on the wire (`format: date`), in the server's tables and in the
phone's. It is the day the person picked, so it needs no time zone, and it reads
the same on every phone. As a timestamp, a 1 a.m. expense in Goa would be the
previous day in UTC and could land on different days on different phones.

Dart has no date-only type, so in the app a day is a `DateTime` at UTC midnight
(`lib/domain/calendar_date.dart`). The generator is told to keep `format: date`
a string, because it would otherwise send a full timestamp and read the day back
as local midnight.

An expense can also carry **when and where it happened**: `occurredAt` (an
instant) and `timeZone` (an IANA name such as `Asia/Kolkata`, from
`flutter_timezone`), both or neither, the way calendar APIs pair `dateTime`
with `timeZone`. A new expense happened now, here; the editor's time is
optional, and picking another day clears it, because that time is no longer
known. The server keeps the pair together (the request schema and a CHECK) and
checks the zone is one its runtime knows.

It orders a day's expenses and is shown on the viewer's own clock. It decides
nothing else, since it comes from a device clock, and `createdAt` stays the
server's own "when this was stored". Two things are deliberately left out for
now:

- **Showing a time on the clock where it happened** ("9:40 pm +07" when viewed
  from another zone). It needs the IANA database on the device. The stored
  `timeZone` keeps that possible later.
- **Checking `entryDate` against the moment on the server.** The device and
  the server each carry their own time zone rules, which disagree for a while
  after a country changes them; a refused expense near midnight would be
  stranded for a field that is only displayed.

---

## How people and groups look

A profile (in D1) and a group (in its object) each carry the same **avatar**
columns, declared once in `server/src/db/appearance.ts`: `avatarKind` —
`initials`, `emoji`, `icon` or `photo` — plus the one field that kind reads,
and `avatarColor`. Exactly the kind's own field is set and every other is
null, the same shape as an event's payload; a CHECK in each table and a Zod
refinement on each body hold that. `avatarColor` is null until somebody picks
a hue, and the device then derives one from the id with a fixed hash
(`hueFor`), so an avatar never changes colour by itself and looks the same on
every device. Icons are a closed list of Material Symbols names, generated
into a Dart enum like every other vocabulary; an emoji is any single
pictographic grapheme.

A group also has a **cover**. `coverKind: generated` stores nothing else: the
device draws it from the group's hue and the icons of the categories it
spends on most, laid out by a generator seeded with the group's id. It
changes as the spending does, and there is no asset to keep.

Changing how a group looks is a group write like a rename, but appends no
event: the activity feed is about the money and the people.

**Photos are in the shape and switched off.** `avatarPhoto` and `coverPhoto`
hold a key in a media store that does not exist yet, and both refinements
refuse any non-null key. Turning uploads on is an R2 binding, an upload
route that returns a key, and replacing that refusal with a check that the
key names an uploaded object, plus the device's picker, resizing and upload.
No column changes, so no migration and no device rebuild.

---

## Sync is event-triggered, never polled

The client syncs on real triggers — screen open, pull-to-refresh, a data-only
push waking the device — and asks each group's object for everything after its
cursor, as one-shot requests.

This is a cost decision as much as a correctness one. Request volume from sync
is the line that scales with usage here; Durable Object compute, storage and
push sends are not. A fixed-interval poll turns "the screen is open" into billed
requests whether or not anything changed.

There is no standing WebSocket, even in the foreground. An object's job is
serializing writes correctly, and that guarantee holds over a plain request just
as well as over a socket — so the socket has to earn its keep separately, and it
does not: mobile drops sockets on backgrounding, so it would reconnect on nearly
every resume, which is the same event a plain fetch already rides.

---

## Auth

Better Auth on D1, with sessions in the same database. There is no
JWT-to-database-role bridge to build, because nothing downstream reads a role.

**Two transports, one session.** The web holds a first-party `HttpOnly` cookie —
possible only because the site, the client and the API share an origin. Android
holds a bearer token. The token arrives in the `set-auth-token` **response
header**; the `token` field in the response body is the unsigned first half of
one and is not a credential.

**The identity endpoints are ours, not Better Auth's** — `/api/identity/
guest`, `/session`, `/sign-out`, `/google`, `/google/redirect`, `/email`,
`/email/verify`, `/reauth`, `/reauth/verify`. Attaching an identity to a guest
session and signing in to an existing account are opposite outcomes: one keeps
the account id, the other replaces the session. Better Auth's own endpoints will
do either without saying which happened, so these wrap it and report the outcome
by comparing account ids, and refuse a sign-in that replaces the session until
the caller has said it asked.

When a guest signs in to an account that already existed, the anonymous
plugin's `onLinkAccount` hands the guest's places to that account
(`handOverGuest` in `server/src/forget.ts`, `handOver` in the group object) and
ends the guest. In a group both were already in, the guest's place stays as a
placeholder, since two places cannot become one row. The guest's local ledger
file is left on the device, unreachable; its groups arrive again under the
account that inherited them.

A session lasts a year from its last use (`expiresIn`, extended at most daily
by `updateAge`): the app is opened for trips, and a guest whose session lapses
can never get back in. A session is a row, so a long one is still revocable,
but holding one is not proof enough to delete the account behind it. An account
with an address must have signed in within ten minutes: `/identity/reauth`
sends a code to its own address, and `/identity/reauth/verify` trades it for a
fresh session and ends the old one. A guest has nothing to confirm with and
deletes without it.

The Worker resolves a session to a profile id and passes it to the group's
object, which checks its own membership list. The Worker's check is a first
pass; the object's is authoritative.

---

## Push

The group's own object calls FCM directly, inside `ctx.waitUntil`, after its
write has committed — and it reads the events it *actually appended*, so an edit
that changed nothing notifies nobody without anyone having to arrange that.
Who to wake is one D1 query by group id — device tokens joined to the
membership index — rather than a list of recipients bound one by one.

No queue in front of it. Notification volume is proportional to ledger writes,
which is a small fraction of request volume, so a queue was never buying cost.
What it would buy is retry, durability across an eviction, and backpressure —
and an occasionally dropped notification is an acceptable loss here in exchange
for one fewer moving part. If that ever stops being true it is a same-shaped
swap: `ctx.waitUntil(send(...))` becomes `env.QUEUE.send(...)` behind the same
call site.

An access token is minted from the service-account key with `jose` and cached in
KV under one key, so a hundred groups notified at once do not mint a hundred
tokens.

---

## Cron: two schedules

`0 4 * * *` refreshes exchange rates, then keeps the last year of them
complete: any stretch of more than a week with no publication (all of it, on a
new deployment) is fetched whole in one range request. A rate more than a week
older than a day does not answer for that day, on the server or the device.
`0 5 * * *` collects abandoned guest
accounts (over ninety days old, in no group, no session used in ninety days) and
finishes any account deletion a request started and did not complete.

There is deliberately no nightly dormancy sweep. A Durable Object sets its own
alarm, so each group carries its own clock: one wake-up in three months rather
than ninety nightly scans that find nothing to do. The alternative — a cron
that asks every group whether it has gone quiet — is a fan-out proportional to
the number of groups, paid every night, to discover that almost none of them
have.

---

## Serving

Static assets are served ahead of the Worker script, so a request for
`main.dart.js` never invokes it. `run_worker_first` is set for `/api/*` only, so
an API call is never an asset lookup that misses first — and no file the web
build emits can shadow an endpoint.

A path under `/app` that matches no asset is answered by the Worker with the
client's own document, by hand. None of the platform's three `not_found_handling`
settings answers the right document: two of them would hand `/app/join/<token>`
the landing page or the 404 page, and that URL is what an invite link *is*.

`site/_headers` carries cross-origin isolation for `/app/*` only — it is what
lets `sqlite3.wasm` use `SharedArrayBuffer`, and the marketing pages at the root
neither need it nor want it. Those headers do survive the Worker-assembled
fallback; that is measured rather than assumed, and asserted by the integration
suite, because losing it would break the local-first database for exactly the
people arriving by invite link.

---

## Cross-group totals are computed on the device

No cross-object materialization and no denormalized balance table in D1. The
client already holds every group it belongs to, so "what do I owe overall" is a
wider fold over the same local entries, grouped by counterparty instead of by
group — derived on every read, never stored, so two devices with the same data
compute the same answer.

Reads outnumber writes roughly 50:1. Putting the reads on devices people already
own is what makes "free forever" a structure rather than a hope.

---

## Three places the obvious design is wrong

- **The rate window has to reach backwards.** A high-water-mark cursor cannot
  deliver a day *older* than the ones already held — which is exactly what a
  backfill produces, since a backfill exists to fetch a date somebody backdated
  past the window. A cursor alone makes the whole backfill path decorative:
  requested, fetched, unreachable. The client reaches back once to the oldest
  expense holding no rate, and records a floor so a date no provider will ever
  answer widens the window one time instead of on every sync forever.
- **The rate writer is a singleton, and has to be.** KV is last-write-wins, so
  a daily run and an on-demand backfill rebuilding the same month from two
  reads would silently drop whichever landed first, and the only symptom would
  be a month quietly missing a currency. One writer removes the race instead of
  detecting it.
- **A table of rate providers would be worse than code.** Rows reorderable
  without a deploy sound flexible, but there is no interface to edit them with
  and every change is a migration anyway — so it is configuration with all the
  cost of a schema and none of the benefit. The waterfall is a list in a file.
  `provider_health` is a table, because "why is AED missing" has to be
  answerable from outside the code.

---

## What is intentionally not here

No queue in front of push, no WebSocket, no server-side balances view, no
cross-object aggregation, and no portability seam.

The last one is a commitment rather than an omission: the object is written in
the shape the platform wants, and PRINCIPLES.md #5 states the consequence
rather than implying a self-host path.

The one storage rule that governs everything else: derive from the ledger on
every read, rather than storing a number that can drift.
