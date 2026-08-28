import 'package:drift/drift.dart';

import '../../domain/activity/snapshot_diff.dart';
import '../../domain/models/entry_event.dart';
import '../../domain/models/entry_snapshot.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Reads the activity log.
///
/// What is stored is a chain of snapshots -- what each expense looked like
/// after each change to it. What a feed wants is the difference between
/// consecutive links. Turning one into the other is this class's whole job, and
/// it is deliberately the only place that does it, so a line reads identically
/// whether it came from the server's record or this device's provisional one.
///
/// No write path here, and that is now literal rather than a convention: the
/// server holds no insert grant for any client, and locally the only writer is
/// `writeEntryInTransaction`, inside the same transaction as the entry itself.
final class DriftActivityRepository {
  DriftActivityRepository(this._db);

  final AppDatabase _db;

  /// A group's feed, newest first.
  ///
  /// Capped rather than unbounded: this is a record to consult, not a list to
  /// scroll to the beginning of time, and a busy group would otherwise build
  /// every row it has ever produced to render a screenful.
  Stream<List<EntryEvent>> watchGroup(String groupId, {int limit = 200}) {
    final window =
        (_db.select(_db.entrySnapshots)
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

    return window.asyncMap((rows) async {
      if (rows.isEmpty) return const <EntryEvent>[];

      // Every snapshot needs the one before it to be readable as a change, and
      // the one before it may well sit outside the window -- an expense edited
      // today was created months and hundreds of rows ago. Fetching the history
      // of just the expenses on screen keeps that bounded without letting the
      // oldest line in the window misread as a creation.
      final entryIds = {for (final row in rows) row.entryId};
      final history = await _historyOf(entryIds);

      return [
        for (final row in rows)
          describeSnapshot(
            previous: _predecessor(history[row.entryId]!, row.id),
            current: row.toDomain(),
          ),
      ];
    });
  }

  /// One expense's history, oldest first -- the order it happened in.
  Stream<List<EntryEvent>> watchEntry(String entryId) =>
      (_db.select(_db.entrySnapshots)
            ..where((t) => t.entryId.equals(entryId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .watch()
          .map((rows) {
            final chain = [for (final row in rows) row.toDomain()];
            return [
              for (var i = 0; i < chain.length; i++)
                describeSnapshot(
                  previous: i == 0 ? null : chain[i - 1],
                  current: chain[i],
                ),
            ];
          });

  /// The most recent change to one expense, described.
  ///
  /// A one-shot read rather than a stream: the caller is a notification, which
  /// is composed once at the moment it arrives and never rebuilds.
  Future<EntryEvent?> latestFor(String entryId) async {
    final chain =
        await (_db.select(_db.entrySnapshots)
              ..where((t) => t.entryId.equals(entryId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(2))
            .get();

    if (chain.isEmpty) return null;
    return describeSnapshot(
      previous: chain.length > 1 ? chain[1].toDomain() : null,
      current: chain.first.toDomain(),
    );
  }

  /// The full chain for each of [entryIds], oldest first.
  Future<Map<String, List<EntrySnapshot>>> _historyOf(
    Set<String> entryIds,
  ) async {
    final rows =
        await (_db.select(_db.entrySnapshots)
              ..where((t) => t.entryId.isIn(entryIds))
              ..orderBy([
                (t) => OrderingTerm(expression: t.createdAt),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();

    final byEntry = <String, List<EntrySnapshot>>{};
    for (final row in rows) {
      (byEntry[row.entryId] ??= []).add(row.toDomain());
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
