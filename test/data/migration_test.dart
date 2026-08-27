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
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 1);
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
    final snapshot = AppDatabase(await verifier.startAt(1));
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
