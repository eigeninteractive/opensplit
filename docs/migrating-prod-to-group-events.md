# Migrating production to `group_events`

This release edits the migrations in place rather than adding new ones on top,
which keeps `supabase/migrations/` readable by subject and is the right trade
while the app is unreleased. The cost is that `supabase db push` cannot carry
production forward: the files no longer describe a delta from what production
has, they describe a different schema.

So production is rebuilt from the migrations and the rows are moved across by
hand. This document is that procedure.

It assumes the state you actually have: the current schema, and a small number
of closed-testing rows worth keeping.

**If the rows are not worth keeping, skip to
[Throwing it away instead](#throwing-it-away-instead).** It is four commands
and two traps, and the rest of this document is unnecessary.

Either way, read
[Which goes first, the server or the client?](#which-goes-first-the-server-or-the-client)
before you start. The answer changed when the local database started rebuilding
itself, and doing it in the wrong order is how testers end up staring at an
empty app.

---

## Throwing it away instead

Closed testing data is often worth exactly nothing, and a rebuild is far less
risky than a transformation. The whole procedure:

```bash
# Drops every user schema, drops everything in `public`, truncates `auth`, and
# replays supabase/migrations/ in order. Close to what a fresh clone gets, minus
# the accounts — see trap 1. Irreversible, and it will ask.
supabase db reset --linked

# The Edge Function was renamed, so the new one has to exist before anything
# points at it.
supabase functions deploy notify-event
supabase secrets set FCM_PROJECT_ID=<project> \
                     FCM_SERVICE_ACCOUNT="$(cat service-account.json)" \
                     NOTIFY_WEBHOOK_SECRET="$(openssl rand -hex 32)"
```

```sql
-- Secrets are not in the migrations, so a reset always loses these two rows
-- whatever the database held before.
insert into app_settings (key, value) values
  ('notify_function_url',
   'https://<ref>.supabase.co/functions/v1/notify-event'),
  ('notify_webhook_secret', '<the same NOTIFY_WEBHOOK_SECRET>')
on conflict (key) do update set value = excluded.value;
```

```bash
supabase functions delete notify-entry   # once push is confirmed working
supabase test db
```

### Trap 1: the accounts go too

**`supabase db reset --linked` does wipe `auth`.** This is worth stating plainly
because the name says `db reset` and the obvious guess is that it leaves the
platform's own schemas alone. It does not:

```sql
-- pkg/migration/queries/drop.sql, run by reset against the linked project
for rec in
  select * from pg_class c
  where (c.relnamespace::regnamespace::name = 'auth'
         and c.relname != 'schema_migrations' or ...)
    and c.relkind = 'r'
loop
  execute format('truncate %I.%I cascade', ...);
end loop;
```

Every table in `auth` is truncated except `auth.schema_migrations` — so
`auth.users`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens`, the
lot. The schema and its structure survive, so GoTrue keeps working; the accounts
in it do not.

For this path that is a feature, and it means there is nothing to do. Testers
lose their accounts along with their data and sign in fresh, and because
`handle_new_user` fires on the new `auth.users` insert they get a profile
automatically. No profile-restoring SQL is needed.

Two details worth knowing rather than discovering:

- **Access tokens outlive the truncate.** A JWT is verified by signature, not by
  a lookup, so a tester holding an unexpired one keeps making requests as a user
  that no longer exists for up to its lifetime — an hour by default. Their
  writes fail on `profiles` foreign keys rather than on authentication, which
  reads as a sync error. It resolves itself when the token expires and the
  refresh fails.
- **Signing in again gives them a new `id`.** It is a fresh account that happens
  to share an email address, so nothing keyed to the old uuid finds them. That
  is fine here because the old rows are being discarded anyway, and it is
  exactly what makes this trap a problem on the preserve-data path, where the
  dump has to put `auth` back.

### Trap 2: the devices do not know anything happened

This is the one that surprises people, and it is a direct consequence of the
app being local-first rather than a bug.

Wiping the server does not wipe the phones. A tester's app holds its own copy of
every group and expense, renders entirely from it, and will go on showing groups
the server has never heard of — indefinitely, because nothing in the app
interprets "the server does not have this" as "delete it", and it must not: that
is the same signal a permissions problem gives.

Worse, their queued writes reference group ids that no longer exist. The server
refuses those permanently — `23503` and `42501` are both in the client's
permanent set — so they land in dead letters rather than retrying, and the
person sees changes that look saved and never arrive.

So after a wipe, testers need to start clean — and in this particular release
they get that for free, because `schemaVersion` went to 2 and the v1 → v2 step
drops every local table. Installing the update **is** clearing app storage.

That holds only for this release, and only for devices that take it. For a
device that stays on the old build, or a future server wipe that ships no schema
change, the manual answer is the real one: **clear app storage, or uninstall and
reinstall.** The truncated `auth` in trap 1 helps a little, by making their
refresh fail once the access token expires, but it is not a wipe of anything on
the device — tell them.

---

## What changes

| Before | After |
| --- | --- |
| `entry_events` (typed columns, `entry_id`) | `group_events` (`kind`, `subject_id`, `payload jsonb`) |
| — | `group_event_kind` enum |
| — | `group_links`, and five functions around it |
| `tokens_for_entry(entry, actor)` | `tokens_for_group(group, actor)` |
| `notify_entry_change` / `trg_entry_events_notify` | `notify_group_event` / `trg_group_events_notify` |
| `entry_events_read` policy | `group_events_read` policy |
| Edge Function `notify-entry` | Edge Function `notify-event` |

Unchanged, and therefore just carried across: `currencies`, `categories`,
`profiles`, `groups`, `members`, `entries`, `entry_payers`, `entry_shares`,
`fx_rates`, `invites`, `device_tokens`, `app_settings`.

`snapshot_entry` is rewritten but keeps its name and its job.

---

## Before you start

**Take a full backup you can actually restore from.** Everything below is
destructive by design.

```bash
supabase link --project-ref <ref>

# Insurance. Not read by this procedure — the thing that gets you back.
supabase db dump --file backup-schema.sql

# Everything the new schema still has a home for, the old history excluded.
supabase db dump --data-only --file backup-data.sql -x public.entry_events

# The old history, on its own, because it is the one thing that has to be
# transformed rather than restored.
pg_dump "$DATABASE_URL" --data-only --column-inserts \
        --quote-all-identifiers --table=public.entry_events \
        -f entry-events.sql
```

Three files, and the split matters: `backup-data.sql` gets loaded as-is in step
2, and a dump containing `INSERT INTO "public"."entry_events"` would hit a table
that no longer exists in the middle of it.

**`backup-data.sql` contains `auth`, and that is the point.** `supabase db dump`
passes `--schema '*'` and excludes only platform-maintained schemas; `auth` is
not among them, and only `auth.schema_migrations` is excluded by table. So the
dump holds `auth.users` and friends, which is what lets step 2 put the testers
back after the reset truncates them. Check before you rely on it:

```bash
grep -c 'INSERT INTO "auth"."users"' backup-data.sql
```

**Nobody has to stop using the app.** This is a closed test on a handful of
devices, so there is no meaningful window to protect and no need to disable
sync. A client that happens to sync into a half-built schema gets errors it
treats as network failures and retries; that is the behaviour it is designed
for, and once the server is whole the next sweep succeeds. Just do not do this
while somebody is mid-expense and expecting it to land.

---

## Step 1 — Rebuild the schema

```bash
supabase db reset --linked
```

This drops every user schema and every object in `public`, truncates `auth`, and
then replays `supabase/migrations/` in order — the same state a fresh clone
gets, minus the accounts.

**Do not park the old rows in a scratch schema to survive this.** An earlier
version of this document said to copy them into `migration_scratch` first, and
that does not work: the reset drops user schemas by owner, and a schema you
created is owned by `postgres` rather than `supabase_admin`, so it goes with the
rest. The exclusion list is `information_schema`, `pg_*`, `_analytics`,
`_realtime`, `_supavisor`, `pgbouncer`, `pgmq`, `pgsodium`, `pgtle`,
`supabase_migrations`, `vault`, `extensions` and `public` — and nothing you can
add yourself. The old history rides this out in `entry-events.sql`, outside the
database entirely, which is why it was dumped separately.

If your Supabase plan or setup refuses `db reset --linked`, the equivalent by
hand is:

```sql
drop schema public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;
```

followed by `supabase db push`. Note that this really does leave `auth` alone,
unlike the reset — so on this route the testers keep their accounts and step 2
will try to insert `auth.users` rows that already exist. Add `truncate
auth.users cascade;` if you want the two routes to behave the same.

---

## Step 2 — Put the rows back, accounts included

Load the data-only dump, **with triggers off**.

This is the step that goes wrong if it is rushed. The new schema has triggers
that write history — `trg_members_record`, `trg_groups_record`,
`trg_entries_snapshot` and its two siblings. Loading rows with those live would
manufacture a fictional past: every member would appear to have joined at the
moment of the restore, every expense would get a fresh "created" snapshot dated
today, and the balance check would run against a half-loaded ledger.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backup-data.sql
```

**The dump turns the triggers off itself.** `supabase db dump` emits
`SET session_replication_role = replica;` as its first line and `RESET ALL;` as
its last, so there is nothing to pass on the command line here — and nothing
still in effect afterwards, which is why step 3 sets it again.

`ON_ERROR_STOP=1` because psql otherwise carries on past a failed statement and
exits 0, which on a restore means finding out later and from the wrong symptom.

This is also where the testers come back. `auth.users` is in the dump, so the
accounts truncated by the reset are restored with their original ids — which is
what keeps `public.profiles` pointing at real users and lets people carry on in
the app without signing in again. Confirm it before moving on:

```sql
select
  (select count(*) from auth.users)      as accounts,
  (select count(*) from public.profiles) as profiles;
```

Those two should agree, and not because a trigger made them: `handle_new_user`
is inert during the load like every other trigger, so both counts come from the
dump. If `profiles` is short, the restore dropped rows. If `accounts` is zero,
the dump did not contain `auth` at all, and every tester will get a new uuid on
next sign-in with their old rows stranded.

---

## Step 3 — Transform the history

The one real transformation. Each old row becomes a `group_events` row of kind
`entry`, with its typed columns folded into the payload.

First give the old rows somewhere to land. The reset dropped `entry_events`, and
`entry-events.sql` inserts into that exact name, so recreate it — same columns
and types as before, but with none of the foreign keys or defaults, because this
exists to be read once and dropped in step 6:

```sql
create table public.entry_events (
  id           uuid primary key,
  entry_id     uuid        not null,
  group_id     uuid        not null,
  actor_id     uuid,
  created_at   timestamptz not null,
  description  text        not null,
  currency     char(3)     not null,
  amount_minor bigint      not null,
  entry_date   date        not null,
  split_kind   split_kind  not null,
  category_id  uuid,
  notes        text,
  deleted_at   timestamptz,
  payers       jsonb       not null,
  shares       jsonb       not null
);
```

The types are the originals rather than approximations, which matters in two
places: `currency` is `char(3)` and `split_kind` is the enum, not text. The enum
survives because `entries.split_kind` still uses it, so it is recreated by the
migrations before this runs.

If you would rather not take this document's word for the shape — and you
should not, it is the old schema and git is its source of truth:

```bash
git show main:supabase/migrations/20260101000005_entries.sql \
  | sed -n '/create table entry_events/,/^);/p'
```

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f entry-events.sql
```

```sql
set session_replication_role = replica;

insert into public.group_events (
  id, group_id, actor_id, created_at, kind, subject_id, payload)
select
  e.id,
  e.group_id,
  e.actor_id,
  e.created_at,
  'entry'::group_event_kind,
  e.entry_id,
  jsonb_build_object(
    'description',  e.description,
    'currency',     e.currency,
    'amount_minor', e.amount_minor,
    'entry_date',   to_char(e.entry_date, 'YYYY-MM-DD'),
    'split_kind',   e.split_kind,
    'category_id',  e.category_id,
    'notes',        e.notes,
    'deleted_at',   case
                      when e.deleted_at is null then null
                      else to_char(e.deleted_at at time zone 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                    end,
    'payers',       e.payers,
    'shares',       e.shares)
from public.entry_events e
-- Only for expenses that survived the restore. An orphan would fail nothing
-- here, since subject_id is deliberately not a foreign key, but it would show
-- up in the feed as a change to an expense nobody can open.
where exists (select 1 from public.entries x where x.id = e.entry_id);
```

**The date rendering is not cosmetic.** `jsonb_build_object` renders a `date`
under `DateStyle` and a `timestamptz` under the session's `TimeZone`, so writing
them raw here would produce payloads spelled differently from the ones
`snapshot_entry` writes afterwards. The dedup in `snapshot_entry` compares
payloads, and a difference in spelling reads to it as a change — the next edit
to any migrated expense would append a spurious "somebody edited nothing" line.
Use the `to_char` forms above, which are what the function itself uses.

`id` is carried across deliberately. Clients that already hold these rows
recognise them and will not duplicate them.

### Optional: give the people already there a history

Existing members predate the new member events, so the feed will show expenses
appearing in groups nobody visibly joined. If you would rather it did not:

```sql
insert into public.group_events (
  group_id, actor_id, created_at, kind, subject_id, payload)
select
  m.group_id,
  null,                       -- unknowable after the fact; see below
  m.joined_at,
  case when m.profile_id is null then 'member_added' else 'member_joined' end
    ::group_event_kind,
  m.id,
  jsonb_build_object('display_name', m.display_name)
from public.members m
-- The group's first member is whoever created it, and "Ravi joined Ravi's
-- flat" is not news. record_member_event suppresses the same line live.
where m.id <> (
  select m2.id from public.members m2
   where m2.group_id = m.group_id
   order by m2.joined_at, m2.id
   limit 1);
```

`actor_id` is null because who added whom is genuinely not recorded anywhere —
the old schema had no reason to. The feed renders an unattributed line as
"Someone added Priya", which is clumsy but true. Leaving it out entirely is
also defensible; a history that starts when the history started is not a lie.

---

## Step 4 — Turn the triggers back on and check

```sql
set session_replication_role = origin;
```

Then verify, in this order:

```sql
-- Every old row arrived, or you know why it did not.
select
  (select count(*) from public.entry_events) as before,
  (select count(*) from public.group_events where kind = 'entry') as after;

-- The tamper property holds: the newest snapshot of each expense still
-- describes the expense.
select e.id
  from public.entries e
  join lateral (
    select payload from public.group_events v
     where v.subject_id = e.id and v.kind = 'entry'
     order by v.created_at desc, v.id desc limit 1
  ) newest on true
 where newest.payload - 'payers' - 'shares' is distinct from jsonb_build_object(
   'description',  e.description,
   'currency',     e.currency,
   'amount_minor', e.amount_minor,
   'entry_date',   to_char(e.entry_date, 'YYYY-MM-DD'),
   'split_kind',   e.split_kind,
   'category_id',  e.category_id,
   'notes',        e.notes,
   'deleted_at',   case
                     when e.deleted_at is null then null
                     else to_char(e.deleted_at at time zone 'UTC',
                                  'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                   end);
```

The second query must return **no rows**. Any row it returns is an expense
whose newest snapshot disagrees with it, which after a migration means the
transformation lost or changed something.

Then the behaviour, rather than the data:

```sql
-- Balances are computed from entries and have nothing to do with any of the
-- above, so this is a check that step 2 restored the ledger, not step 3.
select * from v_member_balances limit 20;
```

Finally run the suite against the migrated database:

```bash
supabase test db
```

---

## Step 5 — Redeploy the Edge Function

The function was renamed, so the old one keeps running until it is removed and
`app_settings` still points at it.

```bash
supabase functions deploy notify-event
supabase secrets set FCM_PROJECT_ID=... \
                     FCM_SERVICE_ACCOUNT="$(cat service-account.json)" \
                     NOTIFY_WEBHOOK_SECRET="$(openssl rand -hex 32)"
```

```sql
update app_settings
   set value = 'https://<project>.supabase.co/functions/v1/notify-event'
 where key = 'notify_function_url';

update app_settings
   set value = '<the same NOTIFY_WEBHOOK_SECRET>'
 where key = 'notify_webhook_secret';
```

`supabase db reset` replays the migrations, which do not contain your secrets —
so both `app_settings` rows have to be set again whatever the dump held.

Then remove the old function, once notifications are confirmed working:

```bash
supabase functions delete notify-entry
```

---

## Step 6 — Drop the old table

Only after everything above has passed, and after the app has been exercised
against the migrated database.

```sql
drop table public.entry_events;
```

Leaving it is not harmless the way an orphaned table on a phone is. PostgREST
reads the schema to decide what it exposes, so a stray `entry_events` in
`public` is a live endpoint with no RLS policy on it.

---

## The clients also have to move

**This is the part with a deadline attached, and it is easy to miss.**

An older build talks to `entry_events` and `pullEntrySnapshots`. After the
migration that table does not exist, so an older client's sync fails — and it
fails in the worst available way: writes queue in the outbox and look saved to
the person who made them.

**The local database throws itself away.** `AppDatabase.schemaVersion` is 2, and
the v1 → v2 step is drift's own `destructiveFallback`: every local table is
dropped and recreated empty, including the outbox and every sync cursor. The
device then re-pulls each feed from the beginning.
`test/data/migration_test.dart` runs that against a real v1 database and asserts
the emptiness rather than hoping for it.

That is the whole of the local migration, and it decides the order below. An
updated client is not a client with stale data — it is a client with **no**
data, which is fine exactly as long as the server it re-pulls from is the new
one.

Two consequences worth stating plainly:

- **Anything queued and unpushed at update time is gone.** Not carried across,
  not recoverable. On a closed test that is acceptable; it is the reason the
  window below wants to be short.
- **Testers no longer need to clear app storage by hand.** The schema bump does
  it for them, which retires most of [trap 2](#trap-2-the-devices-do-not-know-anything-happened)
  — for the devices that actually take the update.

**The update is marked urgent.** This release is the case `AppUpdateService`
reserves a blocking update for, so it goes out with Play's in-app update
priority at 4:

```
gh workflow run release.yml -f deploy=true -f update_priority=4
```

Priority can only be set through the Publishing API, at upload time, on the
release it ships with — there is no field for it in the Play Console and it
cannot be added afterwards. A build that needed it and did not get it needs
another build.

Note that **merging to `main` does not set it.** `release.yml` runs on every
push to `main`, and on a push `inputs.update_priority` is empty, so priority
falls back to `vars.PLAY_UPDATE_PRIORITY` or `0`. Either set that repository
variable before merging, or merge with deployment disabled and dispatch the
workflow by hand with `-f update_priority=4`.

---

## Which goes first, the server or the client?

**The server.** Then the client, as promptly as Play allows.

This reverses the advice an earlier draft of this document gave, and the reason
it reverses is the local migration above. That advice existed to get the new
client onto devices early so it could carry pending local work across the schema
change. It no longer carries anything: it drops the lot and re-pulls. So there
is nothing left to publish early *for*, and the calculation is now only about
which mismatch you would rather have, and for how long.

| | What breaks | How long you control it |
| --- | --- | --- |
| Server first | Old clients fail to sync. They keep showing their local copy, so the app still looks fine, and writes queue in an outbox the update will discard. | Until each tester updates — Play's timing, not yours. Priority 4 shortens it. |
| Client first | Updated clients have already wiped themselves and find a server that cannot answer. **The app is empty, with a refresh error.** | Until you run the migration — minutes, entirely yours. |

Client-first has the shorter window on paper and the worse failure in practice:
every tester who opens the app in that window sees an empty one. "I lost all my
groups" is a support conversation; "it says it could not refresh" is not. And
you cannot choose when they open it.

Server-first breaks old clients, which is what you want — they are displaying a
history the server no longer has.

**Do not over-engineer the gap.** This is a closed test on a handful of devices
that nobody is actively using. Migrate the server, confirm it with the checks in
step 4, then ship the client. The queued-writes problem in the table above is
real but needs somebody adding an expense in the interval to bite, and on a
tester install that is a thing you can simply ask about rather than design
around. On a live app with real traffic the calculation would be different, and
so would this document.

---

## If it goes wrong

Restore, in this order:

```bash
psql "$DATABASE_URL" -c "drop schema public cascade; create schema public;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backup-schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backup-data.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f entry-events.sql
```

Both data files, because the dumps were split: `backup-data.sql` was taken with
`-x public.entry_events`, so the old history only comes back from the second.
`backup-schema.sql` recreates `entry_events` for it to land in.

The accounts come back with `backup-data.sql` too. If you are rolling back after
the reset has already truncated `auth`, that restore is the only thing that puts
the testers' original ids back — so do not skip it on the grounds that "the
accounts were fine".

Then put `app_settings.notify_function_url` back to `notify-entry` and redeploy
the old function if you had already deleted it.

This is why step 6 is last: while `public.entry_events` is still there you can
redo step 3 without restoring anything. And `entry-events.sql` is still on disk
either way, so the worst case is reloading it.
