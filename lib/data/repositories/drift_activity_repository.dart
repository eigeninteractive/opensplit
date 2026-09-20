import 'package:drift/drift.dart';

import '../../domain/activity/snapshot_diff.dart';
import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group_event.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Reads the record of what has happened in a group.
///
/// Most of what is stored can be read straight off the row: the server saw a
/// member join, so it wrote that a member joined. Expenses are the exception
/// and the reason this class exists. What is stored for them is a chain of
/// snapshots -- what each expense looked like after each change -- because at
/// the only moment the server can observe an expense coherently its
/// before-image is already gone. What a feed wants is the difference between
/// consecutive links, and turning one into the other is this class's whole job.
///
/// It is deliberately the only place that does it, so a line reads identically
/// whether it came from the server's record or this device's provisional one.
///
/// No write path here, and that is literal rather than a convention: the server
/// holds no insert grant for any client, and locally the only writers are
/// `writeEntryInTransaction` and the group repository, each inside the same
/// transaction as the change they describe.
final class DriftActivityRepository {
  DriftActivityRepository(this._db);

  final AppDatabase _db;

  /// A group's feed, newest first.
  ///
  /// Capped rather than unbounded: this is a record to consult, not a list to
  /// scroll to the beginning of time, and a busy group would otherwise build
  /// every row it has ever produced to render a screenful.
  Stream<List<GroupEvent>> watchGroup(String groupId, {int limit = 200}) {
    final window =
        (_db.select(_db.groupEvents)
              ..where((t) => t.groupId.equals(groupId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(limit))
            .watch();

    return window.asyncMap((raw) async {
      final rows = [for (final row in raw) row.toDomain()].nonNulls.toList();
      if (rows.isEmpty) return const <GroupEvent>[];

      // Every expense snapshot needs the one before it to be readable as a
      // change, and the one before it may well sit outside the window -- an
      // expense edited today was created months and hundreds of rows ago.
      // Fetching the history of just the expenses on screen keeps that bounded
      // without letting the oldest line in the window misread as a creation.
      //
      // Only expenses need it. Nothing else here is a diff.
      final entryIds = {
        for (final row in rows)
          if (row.kind == GroupEventKind.entry) row.subjectId!,
      };
      final history = await _historyOf(entryIds);

      return [for (final row in rows) _lineFor(row, history: history)];
    });
  }

  /// One expense's history, oldest first -- the order it happened in.
  Stream<List<GroupEvent>> watchEntry(String entryId) =>
      (_db.select(_db.groupEvents)
            ..where(
              (t) =>
                  t.subjectId.equals(entryId) &
                  t.kind.equals(GroupEventKind.entry.wireName),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .watch()
          .map((raw) {
            final chain = [
              for (final row in raw)
                if (row.toDomain() case final parsed?) parsed.snapshot,
            ];
            return [
              for (var i = 0; i < chain.length; i++)
                _entryLine(
                  previous: i == 0 ? null : chain[i - 1],
                  current: chain[i],
                ),
            ];
          });

  /// The most recent recorded change to one subject, described.
  ///
  /// A one-shot read rather than a stream: the caller is a notification, which
  /// is composed once at the moment it arrives and never rebuilds.
  ///
  /// Two rows rather than one, because an expense line is a difference and the
  /// second row is the other half of it. For every other kind the second row is
  /// fetched and ignored, which is cheaper than a second query shape.
  Future<GroupEvent?> latestFor(String subjectId) async {
    final raw =
        await (_db.select(_db.groupEvents)
              ..where((t) => t.subjectId.equals(subjectId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(2))
            .get();

    final chain = [for (final row in raw) row.toDomain()].nonNulls.toList();
    if (chain.isEmpty) return null;

    final current = chain.first;
    if (current.kind != GroupEventKind.entry) return _lineFor(current);

    return _entryLine(
      previous: chain.length > 1 && chain[1].kind == GroupEventKind.entry
          ? chain[1].snapshot
          : null,
      current: current.snapshot,
    );
  }

  /// Turns one stored row into the line a reader is shown.
  ///
  /// The switch is exhaustive over [GroupEventKind] on purpose: a kind added to
  /// the enum stops this compiling until somebody has decided what it says.
  GroupEvent _lineFor(
    GroupEventRow row, {
    Map<String, List<EntrySnapshot>> history = const {},
  }) => switch (row.kind) {
    GroupEventKind.entry => _entryLine(
      previous: _predecessor(history[row.subjectId] ?? const [], row.id),
      current: row.snapshot,
    ),

    GroupEventKind.memberAdded ||
    GroupEventKind.memberJoined ||
    GroupEventKind.memberLeft ||
    GroupEventKind.memberRenamed => MemberChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      memberId: row.subjectId ?? '',
      kind: row.kind,
      displayName: row.name ?? 'Someone',
      previousName: row.previousName,
    ),

    GroupEventKind.groupRenamed ||
    GroupEventKind.groupArchived ||
    GroupEventKind.groupRestored => GroupChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      kind: row.kind,
      name: row.name ?? '',
      previousName: row.previousName,
    ),

    GroupEventKind.linkCreated || GroupEventKind.linkRevoked => LinkChanged(
      id: row.id,
      groupId: row.groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      isProvisional: row.isProvisional,
      kind: row.kind,
    ),
  };

  /// An expense line: the difference between two snapshots.
  EntryChanged _entryLine({
    required EntrySnapshot? previous,
    required EntrySnapshot current,
  }) {
    final event = describeSnapshot(previous: previous, current: current);
    return EntryChanged(
      id: event.id,
      groupId: event.groupId,
      actorId: event.actorId,
      createdAt: event.createdAt,
      isProvisional: event.isProvisional,
      entryId: event.entryId,
      kind: event.kind,
      changes: event.changes,
    );
  }

  /// The full snapshot chain for each of [entryIds], oldest first.
  Future<Map<String, List<EntrySnapshot>>> _historyOf(
    Set<String> entryIds,
  ) async {
    if (entryIds.isEmpty) return const {};

    final rows =
        await (_db.select(_db.groupEvents)
              ..where(
                (t) =>
                    t.subjectId.isIn(entryIds) &
                    t.kind.equals(GroupEventKind.entry.wireName),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.createdAt),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();

    final byEntry = <String, List<EntrySnapshot>>{};
    for (final row in rows) {
      final parsed = row.toDomain();
      if (parsed == null) continue;
      (byEntry[parsed.subjectId!] ??= []).add(parsed.snapshot);
    }
    return byEntry;
  }

  /// What [chain] recorded immediately before the snapshot with [id], or null
  /// if that snapshot is the first thing ever recorded about the expense --
  /// which is what makes it a creation.
  static EntrySnapshot? _predecessor(List<EntrySnapshot> chain, String id) {
    final at = chain.indexWhere((snapshot) => snapshot.id == id);
    return at <= 0 ? null : chain[at - 1];
  }
}
