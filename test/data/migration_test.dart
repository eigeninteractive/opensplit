import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/sync_session.dart';
import 'package:test/test.dart';

import 'generated_migrations/schema.dart';

import '../harness.dart';

/// Guards the one thing a local-first app cannot recover from.
///
/// The device holds the only copy of anything recorded offline and never
/// pushed, so a schema change that drops a table takes real money with it —
/// and there is no server-side backup to restore from, by design.
///
/// The committed snapshot in `drift_schemas/` is what makes a future migration
/// testable at all. Reconstructing "what v1 looked like" after the fact, from a
/// schemaVersion bump nobody wrote down, is guesswork; that is the mistake this
/// file exists to have already avoided.
///
/// When [AppDatabase.schemaVersion] goes to 2:
///
///   dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
///   dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
///
/// then add a `1 -> 2` case here.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the committed snapshot still opens', () async {
    final connection = await verifier.startAt(2);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 2);
  });

  test('a v1 install comes back empty rather than broken', () async {
    // The question this file exists to answer: what happens to somebody who
    // already had the app when the schema changed underneath them.
    //
    // A v1 database is seeded with real rows, opened by the current code, and
    // then used. Before the rebuild existed, the first query here failed with
    // "no such table: group_events" -- not at open, which is why nothing
    // earlier in a launch would have caught it.
    final schema = await verifier.schemaAt(1);
    const at = "'2026-01-01T00:00:00.000Z'";

    schema.rawDatabase.execute(
      'insert into groups (id, name, default_currency, created_at, updated_at) '
      "values ('g1', 'Flat 4B', 'INR', $at, $at)",
    );
    schema.rawDatabase.execute(
      'insert into entry_snapshots (id, entry_id, group_id, created_at, '
      'description, currency, amount_minor, entry_date, split_kind, payers, '
      "shares) values ('ev1', 'e1', 'g1', $at, 'Dinner', 'INR', 40000, $at, "
      "'equal', '[]', '[]')",
    );
    // A device that had already synced everything: without this the re-pull
    // below would be trivially true.
    schema.rawDatabase.execute(
      "insert into sync_cursors (feed, cursor) values ('entries:g1', $at)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // Drift runs the rebuild on the first statement, not at open.
    final events = await db.customSelect('select * from group_events').get();
    expect(events, isEmpty, reason: 'rebuilt, not migrated');

    final groups = await db.select(db.groups).get();
    expect(
      groups,
      isEmpty,
      reason: 'the local copy is a cache; the server still has this group',
    );

    final old = await db
        .customSelect(
          "select name from sqlite_master where name = 'entry_snapshots'",
        )
        .get();
    expect(old, isEmpty, reason: 'and nothing of the old shape is left behind');

    // How the device gets its data back, which is the other half of the
    // policy. Every feed's cursor is gone, so the next sync asks each one from
    // the beginning rather than from where this device had got to -- and
    // groups come from the server's own list, so even one this device never
    // held arrives.
    final cursors = await db.select(db.syncCursors).get();
    expect(cursors, isEmpty, reason: 'every feed re-pulls from the beginning');

    // And it is allowed to. sync_sessions is emptied with everything else, and
    // a missing row reads as enabled -- so a rebuilt device syncs rather than
    // sitting there suspended.
    final session = await readSyncSession(db);
    expect(session.enabled, isTrue);
  });

  test('the search index does not survive the rebuild', () async {
    // The subtle half, and the reason the rebuild reads sqlite_master rather
    // than dropping the entities the current code declares.
    //
    // entries_fts is an external-content fts5 table: it stores terms against
    // `entries` rowids and reads the text back through them. Drop and recreate
    // `entries` underneath it and every rowid it holds points at nothing --
    // and because it is created with IF NOT EXISTS, a surviving index is never
    // replaced. Searching then returns hits for expenses that are not there,
    // which was measured rather than assumed: one hit against an empty table.
    //
    // It is also the one orphan that could not simply be left behind. A table
    // the new schema no longer knows about is dead weight; a stale search
    // index is a wrong answer.
    final schema = await verifier.schemaAt(1);
    const at = "'2026-01-01T00:00:00.000Z'";

    schema.rawDatabase.execute(
      'insert into groups (id, name, default_currency, created_at, updated_at) '
      "values ('g1', 'Flat 4B', 'INR', $at, $at)",
    );
    schema.rawDatabase.execute(
      'insert into members (id, group_id, display_name, joined_at, updated_at) '
      "values ('m1', 'g1', 'Ravi', $at, $at)",
    );
    schema.rawDatabase.execute(
      'insert into entries (id, group_id, kind, description, currency, '
      'amount_minor, entry_date, split_kind, created_by, created_at, '
      "updated_at) values ('e1', 'g1', 'expense', 'Zanzibar', 'INR', 100, "
      "$at, 'equal', 'm1', $at, $at)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    final hits = await db
        .customSelect(
          "select rowid from entries_fts where entries_fts match 'Zanzibar'",
        )
        .get();
    expect(
      hits,
      isEmpty,
      reason: 'a rebuilt index cannot still be answering for the old rows',
    );
  });

  test('a rebuilt database is the one a new install gets', () async {
    // The rebuild goes through the same path as onCreate, and this is what
    // holds it there. Dropping the tables and calling createAll would pass a
    // column comparison and still leave a device with no search index, which
    // is not a drift table and so is invisible to one.
    final schema = await verifier.schemaAt(1);
    final rebuilt = AppDatabase(schema.newConnection());
    addTearDown(rebuilt.close);
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);

    expect(await _columnsByTable(rebuilt), await _columnsByTable(fresh));

    // Deliberately no assertion about currencies. Neither database has any:
    // they are the server's now, and a rebuilt device gets them from its next
    // sweep exactly as a new install does -- which is the same answer, and the
    // point of the comparison above.
    final index = await rebuilt
        .customSelect(
          "select name from sqlite_master where name = 'entries_fts'",
        )
        .get();
    expect(index, hasLength(1), reason: 'and the search index rebuilt');
  });

  test('the committed snapshot still matches the schema in code', () async {
    // What the test above does not do, despite reading as though it does.
    // `migrateAndValidate` from 1 to 1 runs no migration and then compares the
    // generated helper against itself, so it passes whatever the code says --
    // a column renamed in place sailed through it.
    //
    // Column names per table, rather than the DDL. The generated helper writes
    // every DateTime as INTEGER while this database stores them as ISO text,
    // so comparing `sqlite_master` compares two spellings of the same schema
    // and reports a difference on every table, forever. Names are the part
    // that actually owes a migration when it changes.
    final snapshot = AppDatabase(await verifier.startAt(2));
    addTearDown(snapshot.close);
    final code = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(code);
    addTearDown(code.close);

    expect(
      await _columnsByTable(code),
      await _columnsByTable(snapshot),
      reason:
          'Run `dart run drift_dev schema dump` and regenerate the helpers.',
    );
  });

  test('schemaVersion matches the newest committed snapshot', () {
    // A bump without a dump leaves the next migration untestable. Catching it
    // here costs one line; catching it after release costs somebody's data.
    expect(
      AppDatabase(NativeDatabase.memory()).schemaVersion,
      GeneratedHelper.versions.last,
      reason:
          'Run `dart run drift_dev schema dump` and regenerate the helpers.',
    );
  });
}

/// Every table's column names, as SQLite itself reports them.
///
/// The full-text index and its shadow tables are excluded. They are created by
/// a raw statement in [AppDatabase]'s `onCreate` rather than declared as drift
/// tables, so the schema helper generated from the dump does not know about
/// them and never will — their absence from the snapshot is correct, not drift.
Future<Map<String, List<String>>> _columnsByTable(AppDatabase db) async {
  final tables = await db
      .customSelect(
        "select name from sqlite_master where type = 'table' "
        "and name not like 'sqlite_%' and name not like '%_fts%' "
        'order by name',
      )
      .get();

  return {
    for (final table in tables)
      table.read<String>('name'): [
        for (final column
            in await db
                .customSelect(
                  'pragma table_info(${table.read<String>('name')})',
                )
                .get())
          column.read<String>('name'),
      ],
  };
}
