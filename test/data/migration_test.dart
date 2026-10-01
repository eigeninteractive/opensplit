import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/sync_session.dart';
import 'package:test/test.dart';

import 'generated_migrations/schema.dart';

import '../harness.dart';

/// Guards the one thing a local-first app cannot recover from.
void main() {
  late SchemaVerifier verifier;

  /// The newest committed snapshot, taken from the helper rather than written
  /// down.
  final current = GeneratedHelper.versions.last;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the committed snapshot still opens', () async {
    final connection = await verifier.startAt(current);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, current);
  });

  test('a v1 install comes back empty rather than broken', () async {
    // The question this file exists to answer: what happens to somebody who
    // already had the app when the schema changed underneath them.
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

    // The old table is still there, and that is accepted rather than missed.
    final orphan = await db
        .customSelect(
          "select name from sqlite_master where name = 'entry_snapshots'",
        )
        .get();
    expect(
      orphan,
      hasLength(1),
      reason: 'documenting the trade, not endorsing it -- see the doc',
    );

    // And it keeps its rows, which is the part of the trade worth stating
    // outright rather than discovering later.
    final rows = await db
        .customSelect('select count(*) as n from entry_snapshots')
        .getSingle();
    expect(
      rows.read<int>('n'),
      1,
      reason: 'the old rows are still sitting there',
    );

    // How the device gets its data back, which is the other half of the policy.
    final cursors = await db.select(db.groupCursors).get();
    expect(cursors, isEmpty, reason: 'every feed re-pulls from the beginning');

    // And it is allowed to.
    final session = await readSyncSession(db);
    expect(session.enabled, isTrue);
  });

  test('the search index does not survive the rebuild', () async {
    // The subtle half, and the reason the rebuild reads sqlite_master rather
    // than dropping the entities the current code declares.
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
    // holds it there.
    final schema = await verifier.schemaAt(1);
    final rebuilt = AppDatabase(schema.newConnection());
    addTearDown(rebuilt.close);
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);

    final rebuiltTables = await _columnsByTable(rebuilt);
    final freshTables = await _columnsByTable(fresh);

    // Every table a new install has, the rebuilt one has, with the same
    // columns.
    for (final table in freshTables.keys) {
      expect(
        rebuiltTables[table],
        freshTables[table],
        reason: '$table differs between a rebuilt device and a new install',
      );
    }
    expect(rebuiltTables.keys.toSet().difference(freshTables.keys.toSet()), {
      'entry_snapshots',
      // Gone in v3, when four per-group keyset cursors became one integer per
      // group.
      'sync_cursors',
    }, reason: 'exactly the known orphans, and no others sneaking in');

    // Deliberately no assertion about currencies.
    final index = await rebuilt
        .customSelect(
          "select name from sqlite_master where name = 'entries_fts'",
        )
        .get();
    expect(index, hasLength(1), reason: 'and the search index rebuilt');
  });

  test('the committed snapshot still matches the schema in code', () async {
    // What the test above does not do, despite reading as though it does.
    final snapshot = AppDatabase(await verifier.startAt(current));
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
