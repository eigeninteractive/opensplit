import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Imported for the generated part file: `textEnum` columns resolve these types
// in database.g.dart, and a part shares the imports of its parent library.
import '../../domain/models/entry.dart';
import '../../domain/split/splitter.dart';
import 'reference_data.dart';
import 'open_database.dart';
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
/// The same Dart runs on both platforms: native SQLite on Android and
/// `sqlite3.wasm` over OPFS on the web. No layer above this one branches on
/// platform.
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
    EntrySnapshots,
    EntryConflicts,
    FxRates,
    Outbox,
    SyncCursors,
    SyncLeases,
    SyncSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the ledger belonging to [accountId].
  ///
  /// The executor is injectable so tests can use an in-memory database, and so
  /// the push background isolate can open the same file the app uses.
  AppDatabase.forAccount(String accountId, {this._resumeSession = true})
    : super(openAccountDatabase(accountId));

  AppDatabase(super.executor) : _resumeSession = false;

  final bool _resumeSession;

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

  /// Re-runs live queries after the background isolate changed this file.
  ///
  /// Drift automatically invalidates streams for writes made through this
  /// connection. It cannot observe writes from the separate connection used by
  /// Android's push isolate, so the foreground explicitly marks its tables as
  /// changed on resume or notification open. [markTablesUpdated] is Drift's
  /// public API for this boundary.
  void refreshAfterExternalSync() => markTablesUpdated(allTables);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
      await _seedReferenceData();
    },

    // Empty because there is nothing to upgrade *from* yet, and spelled out
    // rather than omitted because of what happens the first time there is.
    //
    // A local-first app cannot drop and recreate: the device holds the only
    // copy of anything recorded offline and never pushed. So every schema
    // change from v1 onwards needs a step here, and the way to know a step is
    // right is to run it against a real v1 database — which is what the
    // committed snapshot in `drift_schemas/` is for, and why it is committed
    // now rather than reconstructed later from a schemaVersion bump nobody
    // wrote down.
    //
    //   dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
    //   dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
    //
    // See test/data/migration_test.dart.
    onUpgrade: (m, from, to) async {
      throw StateError(
        'No migration from schema v$from to v$to. Add a step in '
        'AppDatabase.migration and a case in test/data/migration_test.dart '
        'before shipping a schemaVersion bump.',
      );
    },
    beforeOpen: (details) async {
      if (_resumeSession) {
        await (update(syncSessions)..where((t) => t.id.equals('account')))
            .write(const SyncSessionsCompanion(enabled: Value(true)));
      }
      // SQLite disables foreign keys per connection by default, so the
      // `references` declarations in tables.dart would be documentation only.
      // They are what stops an entry_share pointing at a member who is not in
      // the group.
      await customStatement('PRAGMA foreign_keys = ON');

      if (!kIsWeb) {
        // Two isolates open this file: the app, and the push background
        // handler, which wakes with the app closed and syncs before it can say
        // what arrived. The default rollback journal locks the whole database
        // for a writer, so the two would collide as SQLITE_BUSY at exactly the
        // moment there is nobody to retry.
        //
        // journal_mode is persisted in the file, so this is really only set
        // once; busy_timeout is per connection and has to be set every time.
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA busy_timeout = 5000');
      }
    },
  );

  /// Creates the FTS5 index and the triggers that keep it in step.
  ///
  /// Search is local and instant, over data already on the device — no
  /// endpoint, no query cost, and it works with no connection. Searching your
  /// own expense history is not a feature worth charging for.
  ///
  /// An external-content table (`content='entries'`) stores only the index, not
  /// a second copy of the text, so this costs very little space.
  Future<void> _createSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
        description,
        notes,
        content='entries',
        content_rowid='rowid'
      )
    ''');

    // External-content FTS5 tables are not updated automatically; without
    // these the index silently drifts from the table and search starts
    // returning stale or missing rows.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS entries_fts_insert AFTER INSERT ON entries
      BEGIN
        INSERT INTO entries_fts(rowid, description, notes)
        VALUES (new.rowid, new.description, new.notes);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS entries_fts_delete AFTER DELETE ON entries
      BEGIN
        INSERT INTO entries_fts(entries_fts, rowid, description, notes)
        VALUES ('delete', old.rowid, old.description, old.notes);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS entries_fts_update AFTER UPDATE ON entries
      BEGIN
        INSERT INTO entries_fts(entries_fts, rowid, description, notes)
        VALUES ('delete', old.rowid, old.description, old.notes);
        INSERT INTO entries_fts(rowid, description, notes)
        VALUES (new.rowid, new.description, new.notes);
      END
    ''');
  }

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
          CategoriesCompanion.insert(id: c.id, name: c.name, icon: c.icon),
      ]);
    });
  }
}
