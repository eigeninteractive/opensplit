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
# Drops `public` and replays supabase/migrations/ in order — the same thing a
# fresh clone gets. Irreversible, and it will ask.
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

### Trap 1: the accounts outlive the reset

`db reset` drops `public`. It does **not** touch `auth`, so `auth.users` still
holds every tester — while `public.profiles`, which is where their names live,
is now empty. `handle_new_user` fires `after insert on auth.users` and will not
retro-fire for accounts that already exist, so those testers end up with a valid
session and no profile row, which nothing downstream expects.

Pick one. Keep the accounts and give them their profiles back:

```sql
-- The same expression handle_new_user uses, so an account restored here is
-- indistinguishable from one that had just signed up.
insert into public.profiles (id, display_name)
select u.id,
       coalesce(
         nullif(trim(u.raw_user_meta_data->>'display_name'), ''),
         nullif(split_part(coalesce(u.email, ''), '@', 1), ''))
  from auth.users u
on conflict (id) do nothing;
```

Or throw those away too, which is cleaner if the testers are going to reinstall
anyway — and see trap 2 for why they probably are:

```sql
delete from auth.users;
```

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
reinstall.** Deleting `auth.users` in trap 1 helps by invalidating their
sessions, but do not rely on it alone — tell them.

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
supabase db dump --file backup-schema.sql
supabase db dump --file backup-data.sql --data-only
```

Keep both. The second is the one this procedure reads from; the first is the
one that gets you back if it goes wrong.

**Check what you are about to move.** A handful of rows behaves differently
from a million, and knowing which you have decides whether the direct route
below is acceptable:

```sql
select
  (select count(*) from groups)       as groups,
  (select count(*) from members)      as members,
  (select count(*) from entries)      as entries,
  (select count(*) from entry_events) as events;
```

**Take the app out of the way.** There is a window here where the schema is
half-built, and a client syncing into it will get errors it interprets as
network failures and retry. Either do this when nobody is using it, or turn
sync off at the server for the duration.

---

## Step 1 — Park the old history

`group_events` is not a rename of `entry_events`; the columns are different.
Copy the old rows somewhere the rebuild will not touch, before the rebuild
drops them.

```sql
create schema if not exists migration_scratch;

create table migration_scratch.entry_events as
  select * from public.entry_events;

select count(*) from migration_scratch.entry_events;
```

A schema outside `public`, because the rebuild in step 2 drops `public` whole.

---

## Step 2 — Rebuild the schema

```bash
supabase db reset --linked
```

This drops `public` and replays `supabase/migrations/` in order, which is
exactly what a fresh clone gets. `migration_scratch` survives it.

If your Supabase plan or setup refuses `db reset --linked`, the equivalent by
hand is:

```sql
drop schema public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;
```

followed by `supabase db push`.

---

## Step 3 — Put the unchanged rows back

Load the data-only dump, **with triggers off**.

This is the step that goes wrong if it is rushed. The new schema has triggers
that write history — `trg_members_record`, `trg_groups_record`,
`trg_entries_snapshot` and its two siblings. Loading rows with those live would
manufacture a fictional past: every member would appear to have joined at the
moment of the restore, every expense would get a fresh "created" snapshot dated
today, and the balance check would run against a half-loaded ledger.

```sql
set session_replication_role = replica;  -- triggers and FK checks off
```

```bash
psql "$DATABASE_URL" \
  -c "set session_replication_role = replica;" \
  -f backup-data.sql
```

`session_replication_role = replica` has to be set in the **same session** as
the load, which is why it is passed with `-c` rather than run separately.

Skip `entry_events` if your dump contains it — that table no longer exists and
its rows are in `migration_scratch`.

---

## Step 4 — Transform the history

The one real transformation. Each old row becomes a `group_events` row of kind
`entry`, with its typed columns folded into the payload.

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
from migration_scratch.entry_events e
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

## Step 5 — Turn the triggers back on and check

```sql
set session_replication_role = origin;
```

Then verify, in this order:

```sql
-- Every old row arrived, or you know why it did not.
select
  (select count(*) from migration_scratch.entry_events) as before,
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
-- above, so this is a check that step 3 restored the ledger, not step 4.
select * from v_member_balances limit 20;
```

Finally run the suite against the migrated database:

```bash
supabase test db
```

---

## Step 6 — Redeploy the Edge Function

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

## Step 7 — Drop the scratch schema

Only after everything above has passed, and after the app has been exercised
against the migrated database.

```sql
drop schema migration_scratch cascade;
```

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
device then re-pulls each feed from the beginning. `test/data/migration_test.dart`
runs that against a real v1 database and asserts the emptiness rather than
hoping for it.

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

**The best available version is neither, quite:** run the release, let Play
accept the upload, and migrate the server while the release is still processing
and before rollout completes. Play does not make a closed-testing build
installable the instant the upload finishes. Do the migration in that gap and no
tester is ever running a new client against an old server, nor an old client
against a new one for more than that gap. Watch the track in the Play Console
rather than assuming a duration.

If you are on the [throwing it away](#throwing-it-away-instead) path, this is
simpler than it sounds: there is no data to lose on either side, so migrate the
server whenever you like and make sure it is done before testers update.

---

## If it goes wrong

Restore, in this order:

```bash
psql "$DATABASE_URL" -c "drop schema public cascade; create schema public;"
psql "$DATABASE_URL" -f backup-schema.sql
psql "$DATABASE_URL" -c "set session_replication_role = replica;" -f backup-data.sql
```

Then put `app_settings.notify_function_url` back to `notify-entry` and redeploy
the old function if you had already deleted it.

This is why step 7 is last: while `migration_scratch` exists you can redo step 4
without restoring anything.
