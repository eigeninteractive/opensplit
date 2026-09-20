import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:test/test.dart';

import 'generated_migrations/schema.dart';

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

  test('and brings its history with it', () async {
    // The half a schema check cannot see: the shape would be right too if the
    // migration created the new table and dropped the old one, and that would
    // lose everything the device had not pushed.
    //
    // migrateAndValidate is deliberately not used here. It compares the
    // migrated database against the generated helper, which writes every
    // DateTime as INTEGER while this database stores ISO text -- so a table
    // created by the app's own Migrator always reads as a mismatch. The column
    // comparison in the next test is the shape check; this one is about the
    // rows.
    final schema = await verifier.schemaAt(1);
    const at = "'2026-01-01T00:00:00.000Z'";
    const amounts = '[{\"member_id\":\"m1\",\"amount_minor\":40000}]';

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
      "updated_at) values ('e1', 'g1', 'expense', 'Dinner', 'INR', 40000, "
      "$at, 'equal', 'm1', $at, $at)",
    );
    schema.rawDatabase.execute(
      'insert into entry_snapshots (id, entry_id, group_id, actor_id, '
      'created_at, description, currency, amount_minor, entry_date, '
      'split_kind, payers, shares, is_provisional) values '
      "('ev1', 'e1', 'g1', 'm1', $at, 'Dinner', 'INR', 40000, $at, 'equal', "
      "'$amounts', '$amounts', 1)",
    );
    schema.rawDatabase.execute(
      "insert into sync_cursors (feed, cursor) values ('snapshots:g1', $at)",
    );

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // Opening is not enough; drift runs the migration on the first statement.
    final rows = await db
        .customSelect(
          'select kind, subject_id, payload, is_provisional from group_events',
        )
        .get();
    expect(rows, hasLength(1), reason: 'the snapshot came across');

    final row = rows.single.data;
    expect(row['kind'], 'entry');
    expect(row['subject_id'], 'e1');
    expect(
      row['is_provisional'],
      1,
      reason: 'a change this device never pushed is the only copy there is',
    );

    final payload = jsonDecode(row['payload'] as String) as Map;
    expect(payload['amount_minor'], 40000);
    expect(payload['entry_date'], '2026-01-01');
    expect(
      payload['shares'],
      isA<List>(),
      reason: 'an array, not an escaped blob of one',
    );

    final cursors = await db
        .customSelect("select feed from sync_cursors where feed like 'snap%'")
        .get();
    expect(cursors, isEmpty, reason: 'the feed that cursor named is gone');

    final old = await db
        .customSelect(
          "select name from sqlite_master where name = 'entry_snapshots'",
        )
        .get();
    expect(old, isEmpty, reason: 'and the table it came from is gone');
  });

  test('a migrated device and a fresh one agree on the schema', () async {
    final schema = await verifier.schemaAt(1);
    final migrated = AppDatabase(schema.newConnection());
    addTearDown(migrated.close);
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);

    expect(
      await _columnsByTable(migrated),
      await _columnsByTable(fresh),
      reason: 'a device that upgraded must end up where a new install starts',
    );
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
