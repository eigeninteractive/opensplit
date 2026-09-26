import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// For the generated part, which shares this library's imports.
import 'package:opensplit_api/opensplit_api.dart'
    show EntrySnapshot, GroupEventPayload, LinkEventPayload, MemberEventPayload;

import '../../domain/models/kinds.dart';
import 'open_database.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.drift.dart';

/// The activity feed's total order, newest first: `(seq, ordinal)`, with lines
/// the server has not confirmed yet (no `seq`) above everything it has.
final List<OrderingTerm Function($GroupEventsTable)> newestFirst = [
  (t) => OrderingTerm(
    expression: t.seq,
    mode: OrderingMode.desc,
    nulls: NullsOrder.first,
  ),
  (t) => OrderingTerm.desc(t.ordinal),
  (t) => OrderingTerm.desc(t.createdAt),
  (t) => OrderingTerm.desc(t.id),
];

/// [newestFirst], reversed.
final List<OrderingTerm Function($GroupEventsTable)> oldestFirst = [
  (t) => OrderingTerm(
    expression: t.seq,
    mode: OrderingMode.asc,
    nulls: NullsOrder.last,
  ),
  (t) => OrderingTerm.asc(t.ordinal),
  (t) => OrderingTerm.asc(t.createdAt),
  (t) => OrderingTerm.asc(t.id),
];

/// The local journal.
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
  AppDatabase.forAccount(String accountId, {this._resumeSession = true})
    : super(openAccountDatabase(accountId));

  AppDatabase(super.executor) : _resumeSession = false;

  final bool _resumeSession;

  /// Bump this on **any** change to a table in `tables.dart`.
  @override
  int get schemaVersion => 7;

  /// Timestamps are stored as ISO-8601 text rather than Unix seconds.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  /// Re-runs live queries after the background isolate changed this file.
  void refreshAfterExternalSync() => markTablesUpdated(allTables);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),

    // Every schema change rebuilds the local database from empty, and the
    // device re-syncs.
    onUpgrade: (m, from, to) => destructiveFallback.onUpgrade(m, from, to),

    beforeOpen: (details) async {
      if (_resumeSession) {
        await (update(syncSessions)..where((t) => t.id.equals('account')))
            .write(const SyncSessionsCompanion(enabled: Value(true)));
      }
      // SQLite disables foreign keys per connection by default, so the
      // `references` declarations in tables.dart would be documentation only.
      await customStatement('PRAGMA foreign_keys = ON');

      if (!kIsWeb) {
        // Two isolates open this file: the app, and the push background
        // handler, which wakes with the app closed and syncs before it can say
        // what arrived.
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA busy_timeout = 5000');
      }
    },
  );
}
