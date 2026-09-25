# The local database

Everything the app renders comes from a Drift/SQLite database on the device.
This file covers the two things about it that are easy to get wrong and
expensive to discover late.

---

## Bump `schemaVersion` on any change to a table

`AppDatabase.schemaVersion` is not bookkeeping. SQLite keeps the number in the
file, Drift compares it against the one compiled into the app, and **if the two
agree no migration hook runs at all**.

So an install whose schema changed underneath it without a bump opens its old
database, is told nothing is wrong, and fails on the first query against a table
that is not there. The integer is the only thing standing between a schema
change and that crash — not the migration code, which never runs.

Bumping costs a tester one re-sync, so the right instinct is to bump on any
doubt. After bumping:

```bash
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

`test/data/migration_test.dart` fails if the committed snapshot no longer
matches the tables in code, which catches a change nobody recorded. It cannot
catch a snapshot re-dumped at the same version, so that is the one thing to
watch.

### Why a bump is safe right now

`onUpgrade` delegates to Drift's own `destructiveFallback`: every declared
entity is dropped and recreated, so the device starts empty and re-syncs. Only
its upgrade step is borrowed, because that getter returns a whole
`MigrationStrategy` and using it wholesale would replace `beforeOpen` too —
which is where foreign keys, WAL and the session resume are set. That is a **pre-release policy**, and it is fine only while
the installs are testers who can lose their local copy without losing anything:
the ledger is on the server too.

What it throws away is the outbox — writes made offline and never pushed, which
by definition exist nowhere else. Before anybody who is not a tester installs
the app, this has to become a set of ordinary migrations that preserve data.

---

## Never reuse the name of a removed table

**This is the rule to remember.** If a table is removed from `tables.dart`, its
name is spent. Do not give it to a different table later.

The rebuild drops what the schema *declares*. A table the schema has stopped
declaring is never dropped, so it survives on every device that upgrades rather
than reinstalls — with its rows. `entry_snapshots` is the one that exists today,
left behind when the activity record became `group_events`.

An empty table nobody reads costs a few kilobytes and is not worth more code to
remove. The hazard is what happens if the name comes back:

> `Migrator.createAll()` issues **`CREATE TABLE IF NOT EXISTS`**.

So a new table reusing an old name would not be created and would not error. The
app would bind to the orphan — old columns, missing columns, no message — and
fail somewhere far away from the cause. That is the failure this rule exists to
prevent, and it is silent, which is why it is written down rather than left to
be noticed.

`migration_test.dart` asserts the current set of orphans is exactly
`{entry_snapshots}`, so a second one cannot appear unnoticed. If you add to that
set deliberately, add it there and add it here.

### The orphan keeps its rows

`forgetLocalLedger` deletes by name, so signing out does not clear a table it no
longer knows about. That is tolerable because the database file is keyed per
account — those are the same person's rows in a file only they open — and it
would not be tolerable in a shared file. It is another reason the rule above is
about names rather than tidiness.

---

## Full-text search lives in a `.drift` file

`lib/data/local/search.drift` declares the fts5 index and the three triggers
that keep it in step with `entries`.

It is there rather than in `database.dart` because **Drift cannot express an
fts5 table in the Dart table DSL** — the documentation is explicit that it is not
possible — and being a declared entity is what makes the migration drop and
recreate it like anything else. As raw SQL it was invisible to `allSchemaEntities`
and to the schema snapshot, so the rebuild had to know it existed by name.

That mattered more than it sounds. An external-content fts5 index stores terms
against `entries` rowids; drop and recreate `entries` underneath a surviving
index and every rowid points at nothing, and because it is created with
`IF NOT EXISTS` a stale one is never replaced. Searching then returns hits for
expenses that are not there — measured, not assumed, and pinned by a test.

### It needs `build.yaml`

Drift's sqlite module list is empty by default, so `drift_dev` cannot parse
`CREATE VIRTUAL TABLE ... USING fts5` at all. It reports the table as an element
it could not find, which reads like a syntax error and is not one.

The shape matters as much as the contents: `sqlite: modules:` is accepted by
`build_runner` and then **rejected outright** by `drift_dev schema dump`, which
refuses the `sqlite` field beside `sql`. Everything has to go under
`sql.options`, as it does in `build.yaml`.

### There is no server counterpart

The server has no search of any kind and no index that would support one.
Search never leaves the device: no endpoint, no query cost, and it works with no
connection. That `search.drift` has no mirror on the server is the design, not
an omission — a full-text index there would be a second copy of the journal that
could disagree with the one people actually read from.
