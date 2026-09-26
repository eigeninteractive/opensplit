import 'package:drift/drift.dart';

import '../../domain/activity/snapshot_diff.dart';
import '../../domain/models/group_event.dart';
import '../local/database.dart';

/// The activity feed, read from the local mirror of the server's record.
final class DriftActivityRepository {
  DriftActivityRepository(this._db);

  final AppDatabase _db;

  /// A group's feed, newest first.
  Stream<List<GroupEvent>> watchGroup(String groupId, {int limit = 200}) {
    final window =
        (_db.select(_db.groupEvents)
              ..where((t) => t.groupId.equals(groupId) & _readable(t))
              ..orderBy(newestFirst)
              ..limit(limit))
            .watch();

    return window.asyncMap((rows) async {
      // An expense line needs the snapshot before it, which may be far outside
      // the window, so fetch the history of just the expenses on screen.
      final history = await _historyOf({
        for (final row in rows)
          if (row.kind == EventKind.entry) row.subjectId!,
      });
      return [for (final row in rows) _lineFor(row, history: history)];
    });
  }

  /// One expense's history, oldest first.
  Stream<List<GroupEvent>> watchEntry(String entryId) =>
      (_db.select(_db.groupEvents)
            ..where(
              (t) =>
                  t.subjectId.equals(entryId) &
                  t.kind.equalsValue(EventKind.entry),
            )
            ..orderBy(oldestFirst))
          .watch()
          .map(
            (chain) => [
              for (var i = 0; i < chain.length; i++)
                describeSnapshot(
                  previous: i == 0 ? null : chain[i - 1],
                  current: chain[i],
                ),
            ],
          );

  /// The most recent line about one subject, for a notification.
  Future<GroupEvent?> latestFor(String subjectId) async {
    final latest =
        await (_db.select(_db.groupEvents)
              ..where((t) => t.subjectId.equals(subjectId) & _readable(t))
              ..orderBy(newestFirst)
              ..limit(2))
            .get();
    if (latest.isEmpty) return null;

    final current = latest.first;
    if (current.kind != EventKind.entry) return _lineFor(current);
    return describeSnapshot(
      previous: latest.length > 1 && latest[1].kind == EventKind.entry
          ? latest[1]
          : null,
      current: current,
    );
  }

  /// Rows whose kind this build can render.
  static Expression<bool> _readable($GroupEventsTable t) =>
      t.kind.equalsValue(EventKind.unknownDefaultOpenApi).not();

  /// The line a reader is shown for one row. Exhaustive over [EventKind], so
  /// a new kind stops this compiling until somebody decides what it says.
  GroupEvent _lineFor(
    GroupEventRow row, {
    Map<String, List<GroupEventRow>> history = const {},
  }) => switch (row.kind) {
    EventKind.entry => describeSnapshot(
      previous: _predecessor(history[row.subjectId] ?? const [], row.id),
      current: row,
    ),
    EventKind.memberAdded ||
    EventKind.memberJoined ||
    EventKind.memberLeft ||
    EventKind.memberRenamed => MemberChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      memberId: row.subjectId ?? '',
      kind: row.kind,
      displayName: row.member?.displayName ?? 'Someone',
      previousName: row.member?.previousName,
    ),
    EventKind.groupRenamed ||
    EventKind.groupArchived ||
    EventKind.groupRestored => GroupChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      kind: row.kind,
      name: row.group?.name ?? '',
      previousName: row.group?.previousName,
    ),
    EventKind.linkCreated || EventKind.linkRevoked => LinkChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      kind: row.kind,
    ),
    // Filtered out by [_readable]; never reached.
    EventKind.unknownDefaultOpenApi => throw StateError(
      'Unreadable event ${row.id}',
    ),
  };

  /// Each expense's snapshot chain, oldest first.
  Future<Map<String, List<GroupEventRow>>> _historyOf(
    Set<String> entryIds,
  ) async {
    if (entryIds.isEmpty) return const {};

    final rows =
        await (_db.select(_db.groupEvents)
              ..where(
                (t) =>
                    t.subjectId.isIn(entryIds) &
                    t.kind.equalsValue(EventKind.entry),
              )
              ..orderBy(oldestFirst))
            .get();

    final byEntry = <String, List<GroupEventRow>>{};
    for (final row in rows) {
      (byEntry[row.subjectId!] ??= []).add(row);
    }
    return byEntry;
  }

  /// The snapshot recorded just before [id], or null if [id] is the first —
  /// which is what makes it a creation.
  static GroupEventRow? _predecessor(List<GroupEventRow> chain, String id) {
    final at = chain.indexWhere((row) => row.id == id);
    return at <= 0 ? null : chain[at - 1];
  }
}
