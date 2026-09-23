# The Cloudflare architecture (proposed)

This is not built. The app runs on Supabase today; this is the target shape
if the backend ever moves, written down while the reasoning is fresh.

---

## Why not a lift-and-shift

The current authorization model is not "RLS is on" — it is `auth.uid()`
threaded through every policy, `SECURITY DEFINER` helper functions
(`is_group_member`, `is_group_creator`), and trigger-based column guards
(`guard_group_update`, `guard_member_update`) standing in for what RLS
cannot express. None of that ports to Cloudflare: D1 is SQLite, with no
roles, no RLS, and no `auth.uid()` equivalent.

The real decision this architecture makes is not "which database" but
**where the authorization boundary lives**. The answer here is: one Durable
Object per group.

---

## Core model: one Durable Object per group

Each group is a Durable Object, backed by its own SQLite storage, owning
`members`, `entries`, `entry_payers`, `entry_shares`, `group_events`, and
`invites` for that group only.

A Durable Object processes one request at a time, which replaces several
things Postgres needed extra machinery for:

- The optimistic-concurrency check on entry writes (today's
  `p_base_updated_at` compare in `upsert_entry`) becomes a plain conditional
  in the handler — still necessary (a client can be stale against a
  serialized writer), but with no transaction needed to make it safe.
- The column guards (today's `guard_group_update` / `guard_member_update`
  triggers, which exist because RLS can gate rows but not columns and
  `WITH CHECK` cannot see `OLD`) become ordinary functions with real `OLD`
  and `NEW` values.
- Membership checks (today's `is_group_member()`) become "look at my own
  member list" — no cross-table recursion to design around.

### Sync stays event-triggered, not polled

The app already syncs on real triggers — screen open, pull-to-refresh, a
data-only push waking the device (`SyncController.syncGroup` /
`syncAll`) — never a fixed-interval loop. That carries over unchanged: the
client asks a group's Durable Object for events after its cursor on those
same triggers, as one-shot requests.

This matters for cost, not just consistency: request volume from client
sync traffic — not Durable Object compute, not storage, not push sends — is
the line that actually scales with usage on Cloudflare. A fixed-interval
foreground poll would turn "screen is open" into a steady stream of billed
requests whether or not anything changed; event-triggered requests stay
proportional to real activity, which is what keeps this cheap.

No standing WebSocket to the Durable Object, even while the app is in the
foreground. A Durable Object's job here is serializing writes correctly, not
holding a connection — that guarantee holds whether it's reached over a
socket or a plain request, so reaching it over a socket has to earn its
keep on its own. It mostly doesn't: mobile suspends or drops sockets on
backgrounding routinely, so a WebSocket would need to reconnect on almost
every foreground resume anyway, at which point a plain fetch on that same
resume event has done the same job without a reconnect state machine on the
client or hibernation-aware handling on the object. Global data (the group
index, reference data) is read the same way, from D1/KV, on the same
triggers — one transport, one mental model, for both.

Settled/dormant purge (today's `pg_cron` job calling
`purge_settled_dormant_groups`) becomes a Cron Trigger Worker that asks each
candidate DO to check its own state and delete its own storage.

---

## Global data: D1

Small, genuinely cross-group data lives in one relational D1 database:

- `profiles`, `device_tokens`
- a `user_id -> group_ids` index, so listing "my groups" doesn't mean asking
  every Durable Object
- invite-token -> group-id lookup, for redemption before someone is a member
  of anything

---

## Reference data: KV

`currencies`, `categories`, and cached `fx_rates` — read-heavy, no
per-user variation, matching today's `using (true)` policies. Refreshed by a
Worker Cron Trigger hitting the FX provider, replacing the `fetch-fx` edge
function and its `pg_cron` schedule.

---

## Push notifications: `ctx.waitUntil()`, not Queues

A group's Durable Object calls FCM/APNs directly, wrapped in
`ctx.waitUntil()`, right after its own write to storage has committed.
Replaces `notify-event` and the `pg_net`-based fire-and-forget dispatch
(`trg_group_events_notify`) that triggers it today.

This was a deliberate simplification over putting a Queue in front of it:

- Notification volume is proportional to ledger-write events, not to app
  opens or sync checks, and is a small fraction of overall request volume —
  it was never the cost driver, so Queues wasn't buying cost savings.
- A Durable Object is single-threaded for its own JS, but that only blocks
  on synchronous CPU work — an awaited `fetch()` yields the event loop, so a
  pending push send does not stall the next expense write to the same
  group.
- What Queues actually bought was retry-with-backoff, durability across a
  Durable Object eviction or crash, and backpressure against FCM at high
  concurrency. None of those are worth the extra primitive here: an
  occasional silently-dropped notification is an acceptable loss for this
  app, in exchange for one fewer moving part.

If push reliability ever needs to be tighter than that, this is a
same-shaped swap: `ctx.waitUntil(fetch(...))` becomes `env.QUEUE.send(...)`
behind the same call site, with a consumer Worker doing the actual send.
Nothing upstream of it changes.

---

## Auth: Better Auth

Runs in a Worker, sessions in D1. There is no JWT-to-Postgres-role bridge to
build, because there is no RLS to feed it.

Request flow: Worker resolves the session to a profile id, checks group
membership (D1 index, or asks the Durable Object directly), then forwards
the request to that group's DO stub. The Durable Object is the authoritative
check; the Worker's is a first pass — the same defense-in-depth shape as
today's policy-plus-trigger pair, just relocated.

---

## Cross-group aggregation: client-side, not server-side

No cross-DO materialization, no denormalized balance tables in D1.

The client already syncs every group it belongs to
(`SyncController.syncAll()`), so any cross-group view — total owed overall,
net balance with one person across several shared groups — is a wider fold
over the same locally-synced entries, grouped by counterparty instead of by
group. It carries the same guarantee `foldBalances` already gives per group:
derived on every read, never stored, so two devices with the same synced
data compute the same answer.

Anything that needs visibility beyond what the signed-in user can already
see (platform-wide analytics, for instance) is a different, separate
workload — not something this architecture needs to solve.

---

## What is intentionally not carried over

No RLS, no PostgREST, no `SECURITY DEFINER` RPCs, no `pg_cron`, and no
server-side balances view. The one storage pattern that does carry over is
philosophical, not literal: derive from the ledger on every read rather than
storing a number that can drift.
