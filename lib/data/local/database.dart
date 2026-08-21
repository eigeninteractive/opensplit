import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Imported for the generated part file: `textEnum` columns resolve these types
// in database.g.dart, and a part shares the imports of its parent library.
import '../../domain/models/entry.dart';
import '../../domain/models/member.dart';
import '../../domain/split/splitter.dart';
import 'reference_data.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The local journal.
///
/// The client holds the entire history of every group it belongs to, and every
/// read — balances, analytics, search — is a local SQL query. Nothing on any
/// screen waits for the network, which is what makes the app usable on a train
/// in another country and what keeps server cost flat as users are added.
///
/// The same Dart runs on both platforms: native SQLite on Android, and
/// `sqlite3.wasm` over OPFS on the web, courtesy of drift_flutter. No layer
/// above this one branches on platform.
@DriftDatabase(
  tables: [
    Currencies,
    Profiles,
    Groups,
    Members,
    Categories,
    Entries,
    EntryPayers,
    EntryShares,
    FxRates,
    Outbox,
    SyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  /// Timestamps are stored as ISO-8601 text rather than Unix seconds.
  ///
  /// Delta sync compares against the server's `updated_at`, which carries
  /// microseconds. Truncating to whole seconds would make the cursor ambiguous
  /// for rows written in the same second — the client would either re-pull them
  /// forever or skip them.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedReferenceData();
    },
    beforeOpen: (details) async {
      // SQLite disables foreign keys per connection by default, so the
      // `references` declarations in tables.dart would be documentation only.
      // They are what stops an entry_share pointing at a member who is not in
      // the group.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Populates currencies and the global category presets.
  ///
  /// Run at creation rather than fetched on first launch: the app has to be
  /// able to format an amount and categorise an expense before it has ever
  /// reached the network.
  Future<void> _seedReferenceData() async {
    await batch((batch) {
      batch.insertAll(currencies, [
        for (final c in presetCurrencies)
          CurrenciesCompanion.insert(
            code: c.code,
            exponent: c.exponent,
            symbol: Value(c.symbol),
            name: c.name,
          ),
      ]);
      batch.insertAll(categories, [
        for (final c in presetCategories)
          CategoriesCompanion.insert(
            id: c.id,
            name: c.name,
            icon: Value(c.icon),
          ),
      ]);
    });
  }
}

QueryExecutor _openConnection() => driftDatabase(
  name: 'opensplit',
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
