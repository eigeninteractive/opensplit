import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/open_database.dart';
import 'package:test/test.dart';

import '../harness.dart';
import 'generated_migrations/schema.dart';

/// The new ledger starts fresh and preserves its data when reopened.
void main() {
  late SchemaVerifier verifier;
  final current = GeneratedHelper.versions.last;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the committed baseline opens and matches the current schema', () async {
    final snapshot = AppDatabase(await verifier.startAt(current));
    addTearDown(snapshot.close);
    await verifier.migrateAndValidate(snapshot, current);
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final freshSchema = await _schema(fresh);
    final savedSchema = await _schema(snapshot);
    // Generated fixture helpers omit triggers; the runtime schema creates them.
    freshSchema.removeWhere((name, _) => name.startsWith('trigger:'));
    savedSchema.removeWhere((name, _) => name.startsWith('trigger:'));
    expect(freshSchema, savedSchema);
    expect(fresh.schemaVersion, current);
  });

  test(
    'the new account file leaves old storage and queued edits untouched',
    () async {
      final directory = Directory.systemTemp.createTempSync('opensplit-v1-');
      addTearDown(() => directory.deleteSync(recursive: true));
      const account = 'tester';
      final legacyFile = File('${directory.path}/opensplit-$account.sqlite');
      final legacy = GeneratedHelper().databaseForVersion(
        NativeDatabase(legacyFile),
        current,
      );
      try {
        await legacy.customStatement(
          "INSERT INTO groups (id, name, default_currency, created_at) "
          "VALUES ('old-group', 'Old device copy', 'INR', '2026-10-14T00:00:00Z')",
        );
        await legacy.customStatement(
          "INSERT INTO outbox (target, target_id, revision, position) "
          "VALUES ('group', 'old-group', 'old-edit', 1)",
        );
        await legacy.customStatement('CREATE TABLE old_history (id TEXT)');
        await legacy.customStatement(
          "INSERT INTO old_history VALUES ('keep-me')",
        );
        await legacy.customStatement('PRAGMA user_version = 10');
      } finally {
        await legacy.close();
      }
      final legacyBytes = legacyFile.readAsBytesSync();
      final currentFile = File(
        '${directory.path}/${accountDatabaseName(account)}.sqlite',
      );
      final fresh = AppDatabase(NativeDatabase(currentFile));
      try {
        expect(await fresh.select(fresh.groups).get(), isEmpty);
        expect(await fresh.select(fresh.outbox).get(), isEmpty);
        expect(await fresh.select(fresh.groupCursors).get(), isEmpty);
        expect(await fresh.select(fresh.feedCursors).get(), isEmpty);
        expect(
          (await fresh.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          1,
        );
        await seedReferenceData(fresh);
        await fresh
            .into(fresh.groups)
            .insert(
              GroupsCompanion.insert(
                id: 'restored-group',
                name: 'Sakleshpur',
                defaultCurrency: 'INR',
                createdAt: DateTime.utc(2026, 10, 9),
              ),
            );
        await fresh.customStatement(
          "INSERT INTO outbox (target, target_id, revision, position) "
          "VALUES ('group', 'restored-group', 'new-edit', 1)",
        );
      } finally {
        await fresh.close();
      }
      final reopened = AppDatabase(NativeDatabase(currentFile));
      try {
        expect(
          (await reopened.select(reopened.groups).getSingle()).name,
          'Sakleshpur',
        );
        expect(
          (await reopened.select(reopened.outbox).getSingle()).revision,
          'new-edit',
        );
      } finally {
        await reopened.close();
      }
      final other = AppDatabase(
        NativeDatabase(
          File(
            '${directory.path}/${accountDatabaseName('another-tester')}.sqlite',
          ),
        ),
      );
      try {
        expect(await other.select(other.groups).get(), isEmpty);
        expect(await other.select(other.outbox).get(), isEmpty);
      } finally {
        await other.close();
      }
      expect(legacyFile.readAsBytesSync(), legacyBytes);
    },
  );

  test('opening the current baseline preserves local edits', () async {
    final schema = await verifier.schemaAt(current);
    schema.rawDatabase.execute(
      "INSERT INTO groups (id, name, default_currency, created_at) "
      "VALUES ('g', 'Current local edit', 'INR', '2026-10-14T00:00:00Z')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO outbox (target, target_id, revision, position) "
      "VALUES ('group', 'g', 'current-edit', 1)",
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, current);
    expect((await db.select(db.groups).getSingle()).name, 'Current local edit');
    expect((await db.select(db.outbox).getSingle()).revision, 'current-edit');
  });
}

Future<Map<String, List<String>>> _schema(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name, type FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' "
        'ORDER BY name',
      )
      .get();
  return {
    for (final row in rows)
      '${row.read<String>('type')}:${row.read<String>('name')}': [
        for (final column
            in await db
                .customSelect(
                  'PRAGMA table_info("${row.read<String>('name')}")',
                )
                .get())
          column.read<String>('name'),
      ],
  };
}
