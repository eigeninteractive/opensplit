# The backend, as built

One Worker on one origin serves the static site, the Flutter client and the
API. Behind it: one Durable Object per group, a single Durable Object for
exchange rates, a D1 database for the handful of facts that are genuinely
cross-group, and a KV namespace for things that are derived and rebuildable.

This describes what runs. `docs/cloudflare-migration-plan.md` is the plan it was
built from and the argument for each decision; where the two disagree, this one
is right and the differences are listed at the end.
`docs/cloudflare-runbook.md` is how to stand it up.

---

## The decision the whole design turns on

Not "which database" but **where the authorization boundary lives**. The answer
is: one Durable Object per group, which is that group's only writer.

Everything else follows. A Durable Object processes one request at a time and
owns exactly one group's rows, so the three things Postgres needed extra
machinery for become ordinary code:

| Postgres needed | Here it is |
|---|---|
| RLS policies plus `SECURITY DEFINER` helpers, because `is_group_member` recursed through its own policy | reading my own `members` table |
| `guard_group_update` / `guard_member_update` triggers, because RLS gates rows but not columns and `WITH CHECK` cannot see `OLD` | a function with the old and new rows in hand |
| A deferred constraint trigger for `sum(payers) = sum(shares) = amount` | an `if` inside the write |

None of that is cleverness recovered. It is the same rules, written once, where
the data is.

---

## The sequence number

Because the object is a group's only writer, it can hand out a strictly
increasing integer. Every row written by one change shares one `seq`, and a page
of changes is only ever cut between sequence numbers — so a device sees a whole
change or none of it, and can never hold an expense whose shares have not
arrived.

That replaced four `(timestamp, id)` keyset cursors per group per sync, and with
them the entire class of bug where two rows written in the same transaction
straddle a page boundary because their timestamps differ by a microsecond.

One feed still uses a timestamp cursor, and honestly: profiles live in D1, which
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

## Cron: two schedules, not three

`0 4 * * *` refreshes exchange rates. `0 5 * * 0` collects abandoned guest
accounts and reconciles a slice of the D1 index.

There is deliberately no nightly dormancy sweep. Postgres needed one because a
table cannot schedule itself, so a job scanned every group every night. A
Durable Object sets its own alarm, so each group carries its own clock: one
wake-up in three months instead of ninety that find nothing to do, and no
fan-out proportional to the number of groups.

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

## Where this differs from the plan

Four things changed while building, and the plan still describes the original
intent:

- **Reference data is bundled, not in KV.** The plan put currencies and
  categories in KV. They ship inside the Worker script instead, served with an
  ETag and a day's cache — no read, no migration, no way for the two lists to
  disagree with the code that validates against them.
- **Dormancy is a per-object alarm, not a cron sweep.** The plan had a Cron
  Trigger asking each candidate object to check itself, which is a fan-out
  proportional to the number of groups. Each object schedules its own instead.
- **`fx_providers` did not come across.** A table of provider rows, reorderable
  without a deploy, bought nothing: there was no interface to edit it with, and
  every change was a migration anyway. The waterfall is code. `provider_health`
  did come across, because "why is AED missing" is otherwise unanswerable from
  outside.
- **The rate window reaches backwards.** A high-water mark cannot deliver a day
  *older* than the ones already held, which is exactly what a backfill produces
  — so backfill was structurally undeliverable in the design this inherited. The
  client now reaches back once to the oldest expense holding no rate, with a
  floor recording how far it went.

---

## What is intentionally not here

No RLS, no PostgREST, no `SECURITY DEFINER` RPCs, no `pg_cron`, no server-side
balances view, no queue, no WebSocket, and no portability seam.

That last one is a commitment rather than an omission: the object is written in
the shape the platform wants, and PRINCIPLES.md #6 says so instead of promising
a self-host path nobody tests.

One storage principle did carry over from Postgres, and it is the only one that
mattered: derive from the ledger on every read, rather than storing a number
that can drift.
