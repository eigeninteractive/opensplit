# The local database

The app renders from a per-account Drift/SQLite ledger on the device. Its stable
storage name is `opensplit-v1-<accountId>` on Android and in browser OPFS.
The `v1` label identifies this storage baseline and stays fixed when the schema
version changes.

## Storage baseline

The new ledger starts at schema version 1. The updated app never opens the old
`opensplit-<accountId>` databases. Those files remain untouched in app storage;
no table deletion, legacy migration or data copying runs.

On first open, Drift creates the current schema in the new database. Reference
data and the restored server ledger download after signing in. Cursors and the
outbox start empty, so old queued edits cannot enter the new sync session.
Sessions live outside the database; the server reset invalidates them, and normal
session revalidation signs the device out. No manual storage clearing or
reinstall is required.

Edits that never reached the server stay in the unused old database and are not
imported. Sync pending changes before resetting server storage. Reopening the
new database preserves its data and queued edits.

## Schema changes

`AppDatabase.schemaVersion` describes the structure inside the database. It does
not select a database file. Bump it whenever a table changes, keep the same
storage name, and add explicit incremental migrations before releasing.
There is no upgrade handler at the v1 baseline because no earlier schema exists
for this database. Drift's default upgrade handler refuses missing migrations.

For v2 and later, use Drift's step-by-step migration helpers and test upgrades
from supported versions, including users who skip releases. Preserve local data
and pending writes; starting a fresh database is specific to the initial baseline.
New installations create the latest schema directly.

API version numbers are separate from local schema versions. Reopening a ledger
retains pending rows, but does not translate them for a changed server contract.
Each breaking release must test its new request mapping and any necessary data
migration with pending edits. See [API retirement and app updates](api-upgrades.md).

`drift_schemas/drift_schema_v1.json` is a generated schema description, not a
user database or an automatic migration. Generate and retain each released
snapshot and its test fixtures:

```sh
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
```

CI regenerates these files and checks for differences. Keep the v1 baseline when
testing future migrations. Earlier storage snapshots are not needed because the
app does not open those databases. See [Drift migrations](https://drift.simonbinder.eu/migrations/)
and [schema exports](https://drift.simonbinder.eu/migrations/exports/).

`build.yaml` and `AppDatabase.options` both specify ISO-8601 text timestamps.
The generated snapshot therefore describes the same representation the runtime
uses.

## Search

`lib/data/local/search.drift` declares the FTS5 index and the triggers that keep
it in step with expenses. Drift creates them with the rest of the fresh schema.

Drift's SQL parser needs FTS5 under `sql.options.modules` in `build.yaml`.
The `not_shared` builder produces `database.drift.dart` as a plain part, allowing
Riverpod's generator to see the row classes.

Search stays on the device; the server has no search endpoint or matching index.
