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

Two things follow.

**The local database migrates itself.** `AppDatabase.schemaVersion` is 2, and
the v1 → v2 step carries `entry_snapshots` across into `group_events` rather
than dropping it. That matters for exactly one reason: a provisional row
describes a change the device has not pushed, and for an expense whose push was
refused it is the only copy that exists anywhere. See
`test/data/migration_test.dart`, which runs the step against a real v1 database
and checks the rows arrive.

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

Order matters: **publish the client first and give it time to roll out**, then
migrate the server. The reverse leaves every tester on a broken client for
however long Play takes.

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
