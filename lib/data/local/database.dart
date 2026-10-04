import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Named in the generated part, which shares this library's imports.
import 'package:opensplit_api/opensplit_api.dart'
    show
        AvatarColor,
        AvatarIcon,
        AvatarKind,
        CoverKind,
        EntryKind,
        EntrySnapshot,
        EventKind,
        GroupEventPayload,
        LinkEventPayload,
        MemberEventPayload,
        SplitKind;

import '../../domain/avatar.dart';
import 'open_database.dart';
import 'tables.dart';

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
  int get schemaVersion => 10;

  /// Timestamps are stored as ISO-8601 text rather than Unix seconds.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  /// SQLite's `data_version` when this connection last looked.
  int? _dataVersion;

  /// Re-runs live queries if another connection has committed to this file
  /// since the last look: the push handler, which wakes in its own Flutter
  /// engine and so cannot share this connection. Drift sees only the writes
  /// made through it; `data_version` changes for every commit but this
  /// connection's own, so nothing is re-run when nothing else wrote.
  Future<void> noticeWritesElsewhere() async {
    final seen = _dataVersion;
    final now = _dataVersion = await _readDataVersion();
    if (seen != null && seen != now) markTablesUpdated(allTables);
  }

  Future<int> _readDataVersion() async => (await customSelect(
    'PRAGMA data_version',
  ).getSingle()).read<int>('data_version');

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
      _dataVersion = await _readDataVersion();
    },
  );
}

extension GroupState on Group {
  bool get isArchived => archivedAt != null;

  Avatar get avatar => Avatar.fromColumns((
    kind: avatarKind,
    color: avatarColor,
    emoji: avatarEmoji,
    icon: avatarIcon,
    photo: avatarPhoto,
  ));

  /// This group, pictured as [avatar].
  Group withAvatar(Avatar avatar) {
    final (:kind, :color, :emoji, :icon, :photo) = avatar.columns;
    return copyWith(
      avatarKind: kind,
      avatarColor: Value(color),
      avatarEmoji: Value(emoji),
      avatarIcon: Value(icon),
      avatarPhoto: Value(photo),
    );
  }
}

extension ProfileState on Profile {
  Avatar get avatar => Avatar.fromColumns((
    kind: avatarKind,
    color: avatarColor,
    emoji: avatarEmoji,
    icon: avatarIcon,
    photo: avatarPhoto,
  ));

  /// This profile, pictured as [avatar].
  Profile withAvatar(Avatar avatar) {
    final (:kind, :color, :emoji, :icon, :photo) = avatar.columns;
    return copyWith(
      avatarKind: kind,
      avatarColor: Value(color),
      avatarEmoji: Value(emoji),
      avatarIcon: Value(icon),
      avatarPhoto: Value(photo),
    );
  }
}

extension MemberState on Member {
  /// Nobody has claimed this place yet.
  bool get isPlaceholder => profileId == null;

  bool get isActive => leftAt == null;
}
