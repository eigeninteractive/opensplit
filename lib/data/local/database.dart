import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Imported for the generated part file: `textEnum` columns resolve these types
// in database.g.dart, and a part shares the imports of its parent library.
import '../../domain/models/entry.dart';
import '../../domain/split/splitter.dart';
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
    GroupEvents,
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

  /// Bump this on **any** change to a table in `tables.dart`.
  ///
  /// It is not bookkeeping and it is not backward compatibility: SQLite keeps
  /// this number in the file, drift compares it to this one, and if the two
  /// agree no migration hook runs at all. An install whose schema changed
  /// underneath it without a bump therefore opens its old database, is told
  /// nothing is wrong, and fails on the first query against a table that is not
  /// there. That is the whole failure mode, and this integer is the only thing
  /// that prevents it.
  ///
  /// While this is what it is -- see [migration] -- bumping costs a tester one
  /// re-sync and nothing else, so the right instinct is to bump on any doubt.
  /// `test/data/migration_test.dart` fails if the committed schema snapshot no
  /// longer matches the tables in code, which catches the change you forgot to
  /// record; it cannot catch a snapshot re-dumped at the same version, so that
  /// is the one thing to be careful about.
  @override
  int get schemaVersion => 2;

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

  /// Builds the schema from nothing: tables and the search index.
  ///
  /// Shared by the first launch and by [_rebuild], so the two cannot drift —
  /// a rebuilt database is the same database a new install gets.
  ///
  /// It seeds nothing. Currencies and categories used to be written here from
  /// a hardcoded copy of the server's, which is a duplicate that has to be kept
  /// in step by hand and meant a new currency needed an app release. They are
  /// synced now — see `SyncEngine.pullReferenceData`, and
  /// `referenceDataProvider`, which is what stops the app being usable before
  /// they have arrived.
  Future<void> _createFromScratch(Migrator m) async {
    await m.createAll();
    await _createSearchIndex();
  }

  /// Throws the local copy away and builds it again.
  ///
  /// What gets dropped is read out of `sqlite_master` rather than taken from
  /// `allSchemaEntities`, and that distinction is the whole of this method. The
  /// entities are what the *current code* declares; what has to go is whatever
  /// this *file* happens to hold, and after a schema change those are different
  /// sets by definition. Dropping the declared ones leaves every table the new
  /// code no longer knows about sitting there — which is exactly how
  /// `entry_snapshots` survived a rebuild that was supposed to remove it.
  Future<void> _rebuild(Migrator m) async {
    await customStatement('PRAGMA foreign_keys = OFF');
    try {
      Future<List<String>> named(String type) async => [
        for (final row in await customSelect(
          "select name from sqlite_master where type = ? "
          "and name not like 'sqlite_%'",
          variables: [Variable<String>(type)],
        ).get())
          row.read<String>('name'),
      ];

      // Triggers first: one referencing a table that has already gone is an
      // error on the way out, not a no-op.
      for (final trigger in await named('trigger')) {
        await customStatement('DROP TRIGGER IF EXISTS "$trigger"');
      }
      for (final view in await named('view')) {
        await customStatement('DROP VIEW IF EXISTS "$view"');
      }

      // fts5 virtual tables next, because dropping one also removes the four
      // or five shadow tables it keeps beside itself — and dropping one of
      // those directly is an error rather than a tidy-up.
      for (final table in await named('table')) {
        if (table.endsWith('_fts')) {
          await customStatement('DROP TABLE IF EXISTS "$table"');
        }
      }

      // Re-read, because the shadows are gone now and listing them again would
      // be listing tables that no longer exist.
      for (final table in await named('table')) {
        await customStatement('DROP TABLE IF EXISTS "$table"');
      }

      await _createFromScratch(m);
    } finally {
      await customStatement('PRAGMA foreign_keys = ON');
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: _createFromScratch,

    // Every schema change rebuilds the local database from empty, and the
    // device re-syncs.
    //
    // This is a pre-release policy, not a permanent one, and it is written down
    // here because it is the kind of thing that quietly stops being acceptable.
    // It is fine exactly while the only installs are testers who can lose their
    // local copy without losing anything: the ledger lives on the server too,
    // so a rebuild costs a sync rather than data.
    //
    // The one thing it does throw away is the outbox -- writes made offline and
    // never pushed, which by definition exist nowhere else. That is the cost,
    // it is real, and it is the reason this has to become a real migration
    // before anybody who is not a tester installs the app. See the note on
    // [schemaVersion].
    //
    // Deliberately not `destructiveFallback`, drift's own version of this,
    // which looks like exactly this and is wrong here twice. It drops
    // `allSchemaEntities` -- the tables the *current code* declares, so a table
    // the new code no longer knows about is never dropped at all. And it calls
    // `createAll` rather than onCreate, and replaces onCreate with a default
    // that does the same, so the FTS index and the reference-data seed would be
    // skipped on every path. A device would come back with no search and no
    // currencies, holding whatever tables the old schema had.
    //
    // See [_rebuild] for the first, and [_createFromScratch] for the second.
    // Drift routes a downgrade here too, so a tester moved back to an older
    // build by Play recovers the same way rather than opening a database from
    // the future.
    onUpgrade: (m, from, to) async => _rebuild(m),

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
}
