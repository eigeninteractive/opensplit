import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/server_reference_data.dart';

/// The account a widget test is signed in as.
const testAccountId = '00000000-0000-4000-8000-00000000dead';

/// Everything the app needs to render as a signed-in user with no backend.
const testZone = 'Etc/UTC';

Widget signedInApp({
  required AppDatabase db,
  required SharedPreferences prefs,
  required Widget child,
  String accountId = testAccountId,
}) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    // Supplied directly, so the test's in-memory database is used instead of
    // the per-account file the app would open.
    appDatabaseProvider.overrideWithValue(db),
    signedInProvider.overrideWithValue(true),
    currentAccountIdProvider.overrideWithValue(accountId),

    // "With no backend" said out loud, rather than left to the configuration to
    // imply.
    apiClientProvider.overrideWithValue(null),

    // The platform channel that names this device's zone never answers
    // inside a widget test's fake clock.
    deviceZoneProvider.overrideWith((ref) async => testZone),
  ],
  child: child,
);

/// Gives [db] the reference data a real device gets from its first sync.
Future<void> seedReferenceData(AppDatabase db) async {
  await db.batch((batch) {
    batch.insertAll(db.currencies, [
      for (final c in defaultCurrencies)
        CurrenciesCompanion.insert(
          code: c.code,
          exponent: c.exponent,
          symbol: Value(c.symbol),
          name: c.name,
        ),
    ], mode: InsertMode.insertOrIgnore);
    batch.insertAll(db.categories, [
      for (final c in defaultCategories)
        CategoriesCompanion.insert(id: c.id, name: c.name, icon: c.icon),
    ], mode: InsertMode.insertOrIgnore);
  });
}

/// An in-memory database that already knows what a currency is.
Future<AppDatabase> testDatabase([QueryExecutor? executor]) async {
  final db = AppDatabase(executor ?? NativeDatabase.memory());
  await seedReferenceData(db);
  return db;
}
