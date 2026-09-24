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
  include: {'search.drift'},
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
    GroupCursors,
    FeedCursors,
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
  ///
  /// See `docs/local-database.md`, which also carries the rule this file cannot
  /// enforce: never reuse the name of a removed table.
  @override
  int get schemaVersion => 4;

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
    onCreate: (m) => m.createAll(),

    // Every schema change rebuilds the local database from empty, and the
    // device re-syncs.
    //
    // This is a pre-release policy, not a permanent one, and it is written down
    // because it is the kind of thing that quietly stops being acceptable. It
    // is fine exactly while the only installs are testers who can lose their
    // local copy without losing anything: the ledger is on the server too, so a
    // rebuild costs a sync.
    //
    // What it does throw away is the outbox -- writes made offline and never
    // pushed, which by definition exist nowhere else. That is the cost, it is
    // real, and it is why this has to become a set of ordinary migrations
    // before anybody who is not a tester installs the app. See [schemaVersion].
    //
    // Drift's own `destructiveFallback`, delegated to rather than
    // reimplemented. The getter returns a whole MigrationStrategy, and using it
    // wholesale would replace `beforeOpen` too -- which is where foreign keys,
    // WAL and the session resume are set, none of which this policy has an
    // opinion about. So its upgrade step is borrowed and the rest is ours.
    //
    // It drops what the schema *declares*, so a table removed from
    // `tables.dart` is left behind on devices that upgrade rather than
    // reinstall. Accepted deliberately, and the one rule that keeps it harmless
    // is written down in docs/local-database.md: never reuse the name of a
    // table that has been removed. `createAll` issues CREATE TABLE IF NOT
    // EXISTS, so a reused name would silently bind to the old table rather than
    // fail.
    onUpgrade: (m, from, to) => destructiveFallback.onUpgrade(m, from, to),

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
}
