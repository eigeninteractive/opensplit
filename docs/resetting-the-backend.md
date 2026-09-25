# Resetting the backend

While the app is in closed testing and the rows in production are not worth
keeping, the answer to "the migrations changed shape" is to rebuild rather than
to transform. This is that procedure, and the handful of things about it that
are not obvious.

The short version: **D1 is easy and Durable Objects are not.** D1 has a delete
command, an export, and point-in-time recovery. A Durable Object namespace has
none of those, and there is no command that empties one. Getting that wrong
leaves storage you are billed for and cannot reach.

---

## Why a reset is needed at all

Forward migrations do not need one. `wrangler d1 migrations apply` runs whatever
is new, and each group object applies its own outstanding migrations on first
open after a deploy.

A reset is for the other case: a migration file that has *already run* turning
out to be wrong. There is no down migration on either side, and a group object
that has applied `0003` will never apply a corrected `0003`. Rebuilding is the
only honest answer, and it is cheap only while nobody's records matter.

---

## 1. Take the backup you will not read

```sh
cd server
npx wrangler d1 export opensplit --remote --output backup.sql
```

Insurance, not an input. Nothing below reads it; it exists so that "it turned
out to matter after all" is recoverable.

There is **no equivalent for the Durable Objects**, which is where every ledger
actually lives. `wrangler d1 export` covers the index and the accounts and
nothing else. If a group's contents matter, pull them through the API from a
device before you start.

D1 also has Time Travel, which is a better answer than a file for the thirty
days it covers:

```sh
npx wrangler d1 time-travel info opensplit
npx wrangler d1 time-travel restore opensplit --timestamp <iso8601>
```

---

## 2. Destroy the group objects

This is the part with a sharp edge. A Durable Object namespace is deleted by
deploying a `deleted` tombstone in `exports`, and the platform enforces that the
class is **not present in the Worker code** when you do it. So it is two
deploys, with the tree temporarily missing a class:

```jsonc
// server/wrangler.jsonc — temporarily
"durable_objects": {
  "bindings": [{ "name": "FX", "class_name": "Fx" }]   // GROUP removed
},
"exports": {
  "Group": { "type": "durable-object", "state": "deleted" },
  "Fx": { "type": "durable-object", "storage": "sqlite" }
}
```

with `export { Group }` commented out of `src/index.ts`, then:

```sh
npx wrangler deploy      # the namespace and every group in it are gone
```

Then put both back as they were — `"Group": { "type": "durable-object",
"storage": "sqlite" }` — and deploy again. The second deploy provisions a fresh,
empty namespace under the same name.

Three things worth knowing before you do it:

- **It is not a soft delete and there is no trash.** Every group's members,
  entries, payers, shares and history go at once.
- **The Worker is briefly deployed without a `GROUP` binding.** Every ledger
  request 500s until the second deploy. That is fine for a reset and would not
  be fine for anything else, which is the reason to do both deploys back to
  back and nothing else in between.
- **Lifecycle changes cannot be part of a gradual rollout**, and a version
  containing one cannot be rolled back past. Deploy it on its own.

`npx wrangler delete` is the blunter alternative: it removes the whole Worker
and its namespaces in one command. It also removes the secrets and detaches the
custom domain, so the way back is most of the runbook. Prefer the tombstone.

---

## 3. Rebuild D1

```sh
npx wrangler d1 delete opensplit
npx wrangler d1 create opensplit          # prints a NEW database_id
```

Put the new id in `server/wrangler.jsonc` and commit it, then:

```sh
npx wrangler d1 migrations apply opensplit --remote
npx wrangler deploy
```

Recreating rather than dropping tables by hand, because the migration state
lives in a table of its own and a partial drop leaves `d1_migrations` claiming
work that is no longer there.

### The trap: resetting D1 alone

D1 is an index, not the truth. Wipe it while the group objects survive and every
group still exists, still holds its ledger, and is still billed for its storage
— but nothing can name it. `memberships` is how a device discovers which groups
it is in, and the weekly reconciliation sweep reads that same table to decide
which objects to check, so it cannot find them either.

Nothing reports this. It looks like every account came back empty.

So: **objects first, then D1** — or neither.

---

## 4. Put back what migrations cannot carry

Secrets survive a D1 reset, because they belong to the Worker. They do **not**
survive `wrangler delete`. After one of those, all of step 4 in
[the runbook](cloudflare-runbook.md) again.

KV needs nothing. The rate blobs and the FCM token rebuild themselves — the
token on the next push, the rates on the next 04:00 UTC run or whenever you ask:

```sh
curl -s -X POST https://opensplit.eigeninteractive.com/api/fx/backfill \
  -H 'content-type: application/json' \
  -d "{\"asOf\":\"$(date -u -v-3d +%F)\",\"currency\":\"EUR\"}"
```

### Check it came back

Most of this is automatic. These are the three that fail quietly:

```sh
base=https://opensplit.eigeninteractive.com

# Reference data ships inside the Worker script, so this one cannot actually
# be empty any more — it used to be a table, and an empty table meant nobody
# could create a group at all. Worth a glance to confirm the deploy is the
# build you think it is.
curl -s $base/api/reference | head -c 120

# D1 is bound and writable. A guest sign-in writes a user and a session.
curl -s -X POST $base/api/auth/sign-in/anonymous -H 'content-type: application/json'

# A group object can be created and reached at all.
npx wrangler tail --format pretty
```

---

## It does not reach the devices

A tester's app holds its own copy of every group and expense and renders
entirely from it. Wiping the server does not wipe the phones, and the app goes
on showing groups the server has never heard of — indefinitely, because nothing
treats "the server does not have this" as "delete it", and nothing should: that
is the same signal a permissions problem gives.

Their queued writes then reference ids that no longer exist. The server refuses
those permanently rather than transiently — a refusal carries its own kind, and
a permanent one goes to dead letters instead of retrying — so the person sees
changes that look saved and never arrive.

So a reset needs the devices cleared too: **clear app storage, or uninstall and
reinstall.**

Unless the same release bumps `AppDatabase.schemaVersion`, in which case it is
already handled — the upgrade path is drift's `destructiveFallback`, which drops
every local table, so installing the update *is* clearing app storage. See
[local-database.md](local-database.md).

---

## Order, when a client release goes with it

**Server first.** An updated client has already wiped its local database and
repopulates entirely from the server, so it is not a client with stale data, it
is an empty one until the server it pulls from is the new one. An old client
against a new server merely fails to sync, which is what you want — it is
displaying a history that no longer exists.

Two things about how the client actually ships:

- **Merging to `main` releases.** `release.yml` runs on every push to `main` and
  its deploy steps are gated on `github.event_name == 'push' || inputs.deploy`,
  so a merge deploys the Worker and the web bundle together and uploads to Play
  closed testing with no further action. Reset before merging, not after.
- **A merge cannot set the update priority from the workflow input.**
  `PLAY_UPDATE_PRIORITY` resolves as
  `inputs.update_priority || vars.PLAY_UPDATE_PRIORITY || '0'`, and on a push
  the input is empty, so only the variable decides. It lives on the `production`
  environment rather than at repository level, which matters because a
  repository-level variable of the same name is shadowed by it and would look
  set while doing nothing:

  ```bash
  gh variable list -e production
  gh variable set PLAY_UPDATE_PRIORITY -e production -b 4
  ```

  Priority is settable only through the Publishing API, at upload time, on the
  release it ships with — a build that needed a blocking update and did not get
  one needs another build. The variable persists, so put it back to 0 once the
  release that needed it is out, or every subsequent merge interrupts testers.
