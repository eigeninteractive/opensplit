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
sequence number.

---

## What each store holds

**The group object** (`server/src/db/group/schema.ts`) — `members`, `entries`,
`entry_payers`, `entry_shares`, `events`, `invites`, `group_link`, plus four
tables that exist because the object is a little machine as well as a table:
`counter` (the sequence allocator), `meta` (the group row itself), `tombstone`
(what is left after a purge, so a device that still holds a copy is told to drop
it rather than being refused forever), `outbox` (writes owed to D1) and
`schedule` (the dormancy alarm).

**D1** (`server/src/db/d1/schema.ts`) — `profiles`, `memberships`,
`device_tokens`, `link_tokens`, plus Better Auth's own four tables. Everything
here except `profiles` is a **derived index**: the objects are the truth, and D1
is what makes "which groups am I in" and "what does this token point at"
answerable without asking every object in the account. A weekly sweep checks it
still agrees.

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
Drizzle tables ──drizzle-zod──▶ Zod row schemas ─┐
                  hand-written Zod request bodies ┴─▶ OpenAPI (docs/openapi.json)
    ──openapi-generator──▶ packages/opensplit_api (Dart) ──lib/data/sync/wire.dart──▶ Drift rows
```

- **Rows the server returns are derived from their tables** with drizzle-zod,
  so a column is declared in one place. Overrides give a column its wire type
  where SQLite has none: a timestamp, a date, a named enum, a meaningful range.
- **Request bodies are written out**, because they are narrower than the rows
  they write (no `createdBy`, no `seq`) and carry the validation.
- **The enum vocabularies** (entry, split and event kinds) are one list each in
  the Drizzle schema, used by the column, the Zod enum and so the Dart enum. A
  value a build does not know decodes to the generator's `unknownDefaultOpenApi`
  rather than failing the page.
- **The app uses the generated types directly**, including the error envelope
  (`ApiFailure`) and the activity payloads. `wire.dart` is the only translation,
  and exists because a local row is not a server row: it can exist before the
  server has seen it (null `seq`), it carries the `groupId` a page states once,
  an expense is three tables, and a date is a `DateTime`.
- CI regenerates the contract and the client (`dart run
  tool/generate_api_client.dart --check`) and fails on any difference.

### Required, nullable, optional

**Every body field is required, and `null` is the only way to say "none".** A
generated Dart client cannot send "absent" as distinct from null (it drops a
null optional field), so an optional field would have three states on the
server and two on the device. Updates are therefore `PUT`s of every editable
field, like `ProfileUpdate`. Optional exists only for query parameters, where a
server default is ordinary HTTP.

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

**The three identity endpoints are ours, not Better Auth's** — `/api/identity/
google`, `/email`, `/email/verify`. Attaching an identity to a guest session and
signing in to an existing account are opposite outcomes: one keeps everything on
this device, the other leaves it behind. Better Auth's own endpoints will do
either without saying which happened, so these wrap it and report the outcome by
comparing account ids, and refuse a sign-in that would strand a ledger until the
caller has said it asked.

The Worker resolves a session to a profile id and passes it to the group's
object, which checks its own membership list. The Worker's check is a first
pass; the object's is authoritative.

---

## Push

The group's own object calls FCM directly, inside `ctx.waitUntil`, after its
write has committed — and it reads the events it *actually appended*, so an edit
that changed nothing notifies nobody without anyone having to arrange that.

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

`0 4 * * *` refreshes exchange rates. `0 5 * * 0` collects abandoned guest
accounts and reconciles a slice of the D1 index.

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
the shape the platform wants, and PRINCIPLES.md #6 states the consequence
rather than implying a self-host path.

The one storage rule that governs everything else: derive from the ledger on
every read, rather than storing a number that can drift.
