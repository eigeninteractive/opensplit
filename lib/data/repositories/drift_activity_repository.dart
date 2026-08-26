import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry_event.dart';
import '../local/database.dart';
import '../sync/wire.dart' show changesFromJson;

/// Reads the activity log. There is deliberately no write path.
final class DriftActivityRepository {
  DriftActivityRepository(this._db);

  final AppDatabase _db;

  /// A group's feed, newest first.
  ///
  /// Capped rather than unbounded: this is a record to consult, not a list to
  /// scroll to the beginning of time, and a busy group would otherwise build
  /// every row it has ever produced to render a screenful.
  Stream<List<EntryEvent>> watchGroup(String groupId, {int limit = 200}) =>
      (_db.select(_db.entryEvents)
            ..where((t) => t.groupId.equals(groupId))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.createdAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(limit))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());

  /// One expense's history, oldest first — the order it happened in.
  Stream<List<EntryEvent>> watchEntry(String entryId) =>
      (_db.select(_db.entryEvents)
            ..where((t) => t.entryId.equals(entryId))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());

  EntryEvent _toDomain(EntryEventRow row) => EntryEvent(
    id: row.id,
    entryId: row.entryId,
    groupId: row.groupId,
    actorId: row.actorId,
    // byName would throw on a kind this build has never heard of, taking the
    // whole feed down with it. An unfamiliar event is skipped by the UI
    // instead, which is the lesser failure.
    kind: EntryEventKind.values.asNameMap()[row.kind] ?? EntryEventKind.edited,
    createdAt: row.createdAt,
    changes: row.changes == null
        ? const []
        : changesFromJson(jsonDecode(row.changes!)),
  );
}
