# Resetting the backend

While the app is in closed testing and the rows in production are not worth
keeping, the answer to "the migrations changed shape" is to rebuild rather than
to transform. This is that procedure, and the handful of things about it that
are not obvious.

It replaces a much longer document describing how to carry the old data across.
That document is gone on purpose: it described machinery for a migration nobody
is going to run, and a procedure that is never exercised is a procedure that is
wrong by the time you need it.

---

## The procedure

```bash
supabase link --project-ref <ref>

# Insurance, not an input. Nothing below reads these; they exist so that
# "it turned out to matter after all" is recoverable for a few days.
supabase db dump --file backup-schema.sql
supabase db dump --data-only --file backup-data.sql

# Irreversible, and it will ask.
supabase db reset --linked
```

Then the parts the migrations cannot carry:

```bash
supabase functions deploy notify-event
supabase functions deploy fetch-fx

# Secrets live on the platform, not in the database, so the reset did NOT
# clear them -- but you cannot read one back either, only its digest. Rotating
# is therefore easier than discovering what the old value was.
supabase secrets set FX_FETCH_SECRET="$(openssl rand -hex 32)"
supabase secrets set NOTIFY_WEBHOOK_SECRET="$(openssl rand -hex 32)"
supabase secrets set FCM_PROJECT_ID=<project> \
                     FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
```

```sql
-- Four rows, not two. Each feature no-ops until its pair is set, silently --
-- which is the failure this list exists to prevent: push and the scheduled
-- rate fetch both come back dead from a reset and neither complains.
insert into app_settings (key, value) values
  ('fx_function_url',
   'https://<ref>.supabase.co/functions/v1/fetch-fx'),
  ('fx_fetch_secret',       '<the same FX_FETCH_SECRET>'),
  ('notify_function_url',
   'https://<ref>.supabase.co/functions/v1/notify-event'),
  ('notify_webhook_secret', '<the same NOTIFY_WEBHOOK_SECRET>')
on conflict (key) do update set value = excluded.value;
```

```bash
supabase test db                        # the suite, against the real thing
supabase functions delete notify-entry  # only once push is confirmed working
```

`notify-entry` is the old name and is not in this repo any more, so it will sit
deployed and orphaned in the project until it is deleted by hand.

### Check that it came back

The migrations replay, so most of this is automatic. These three are worth
looking at anyway, because each fails quietly rather than loudly:

```sql
-- Reference data. Not a nicety: the client learns currencies and categories
-- from the server and `groups.default_currency` references `currencies`, so an
-- empty table here means nobody can create a group at all.
select (select count(*) from currencies) as currencies,
       (select count(*) from categories) as categories;

-- Scheduled jobs. `create extension pg_cron` is wrapped in an exception
-- handler that downgrades to `raise notice`, by design, so a project without
-- pg_cron still migrates -- and a project that failed to install it looks
-- identical to one that never had jobs.
select jobname, schedule, active from cron.job order by jobname;

-- Operator configuration, which no migration can restore.
select key from app_settings order by key;
```

Four job names (`opensplit-fetch-fx`, `opensplit-cleanup-anon`,
`opensplit-archive-dormant`, `opensplit-purge-settled`) and four settings keys.

### `seed.sql` runs against production

`[db.seed] enabled = true` in `config.toml`, so `db reset --linked` applies
`supabase/seed.sql` after the migrations — to whatever is linked. It is empty
today, and the comment at the top of it says why: reference data belongs in the
migrations because production needs it too. Keep it that way, or check it before
every reset.

---

## The reset takes the accounts with it

Worth stating because the command is called `db reset` and the reasonable guess
is that it leaves the platform's own schemas alone. It does not. The CLI runs
`pkg/migration/queries/drop.sql` against the linked project, which drops user
schemas and everything in `public`, and then:

```sql
-- truncate tables in auth, webhooks, and migrations schema
where (c.relnamespace::regnamespace::name = 'auth'
       and c.relname != 'schema_migrations' or ...)
  and c.relkind = 'r'
...
execute format('truncate %I.%I cascade', ...);
```

Every table in `auth` except `auth.schema_migrations` — users, identities,
sessions, refresh tokens. The schema survives, so GoTrue keeps working; the
accounts in it do not.

For a throw-it-away reset that is convenient: testers sign in fresh,
`handle_new_user` fires on the new `auth.users` row and gives them a profile,
and there is nothing to restore. Two consequences to know rather than discover:

- **Access tokens outlive the truncate.** A JWT is checked by signature, not by
  a lookup, so a tester holding an unexpired one keeps making requests as a user
  that no longer exists — up to an hour by default. Their writes fail on
  `profiles` foreign keys rather than on auth, which surfaces as a sync error.
  It clears itself when the refresh fails.
- **Signing in again gives them a new `id`.** It is a new account that happens
  to share an email address.

There is no way to keep a scratch schema through this, either: the drop excludes
a fixed list of platform schemas plus anything owned by `supabase_admin`, and a
schema you create is owned by `postgres`. Anything you want to survive a reset
has to leave the database.

---

## It does not reach the devices

A tester's app holds its own copy of every group and expense and renders
entirely from it. Wiping the server does not wipe the phones, and the app will
go on showing groups the server has never heard of — indefinitely, because
nothing treats "the server does not have this" as "delete it", and nothing
should: that is the same signal a permissions problem gives.

Their queued writes then reference ids that no longer exist. The server refuses
those permanently — `23503` and `42501` are both in the client's permanent set —
so they go to dead letters rather than retrying, and the person sees changes
that look saved and never arrive.

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
  so a merge deploys web to Firebase Hosting and uploads to Play closed testing
  with no further action. Reset the database before merging, not after.
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
