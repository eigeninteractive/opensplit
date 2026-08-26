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

  test('the committed snapshot still matches the schema in code', () async {
    // Fails the moment a table or column changes without a new snapshot, which
    // is the only warning there is that a migration is now owed.
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 1);
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
