import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/server_reference_data.dart';

/// The account a widget test is signed in as.
///
/// A fixed uuid rather than a random one so that a failure message naming it is
/// the same failure message every time.
const testAccountId = '00000000-0000-4000-8000-00000000dead';

/// Everything the app needs to render as a signed-in user with no backend.
///
/// A session is not optional any more. The app used to manufacture one on
/// startup, so a test could get away with overriding storage alone; now nobody
/// is anybody until they choose, and a test that skips this lands on the
/// welcome screen and finds none of the widgets it came to look for.
///
/// [signedInProvider] and [currentAccountIdProvider] are overridden rather than
/// the session behind them because there is no auth service in a widget test at
/// all: `authServiceProvider` is null, so the real controller can only ever
/// answer "nobody".
/// Returns a scope, not a list of overrides: `Override` is not part of
/// flutter_riverpod's public API, so it cannot be named in a signature here.
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

    // "With no backend" said out loud, rather than left to the configuration
    // to imply. A null api is the shape a deliberately local-only build
    // produces and every caller already handles.
    //
    // It has to be stated because the api is built from a base URL with a
    // development default: left alone, a signed-in widget test reaches for
    // localhost, fails, and renders "Could not refresh your groups" over the
    // screen it came to look at. Every test using this helper is about what
    // the app does with its own data, so none of them should be deciding
    // anything about a connection.
    remoteLedgerApiProvider.overrideWithValue(null),
  ],
  child: child,
);

/// Gives [db] the reference data a real device gets from its first sync.
///
/// The app no longer ships a hardcoded copy of the server's currencies and
/// categories — it learns them, so that adding a currency does not need a
/// release. Which means a test database starts genuinely empty, and
/// `groups.default_currency` references `currencies`: creating a group without
/// this fails a foreign key.
///
/// That is the production ordering rather than a quirk of the tests. A real
/// device cannot create a group before its first sweep either, which is why
/// `referenceDataProvider` makes the app wait for one. This is the same
/// precondition, arranged directly.
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
