import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

/// Removes a group's cache and queued edits after access definitively ends.
///
/// The caller owns the transaction and checks the active sync session first.
Future<void> removeGroupInTransaction(AppDatabase db, String groupId) async {
  final memberIds = db.selectOnly(db.members)
    ..addColumns([db.members.id])
    ..where(db.members.groupId.equals(groupId));
  final entryIds = db.selectOnly(db.entries)
    ..addColumns([db.entries.id])
    ..where(db.entries.groupId.equals(groupId));
  await (db.delete(db.outbox)..where(
        (row) =>
            (row.target.equalsValue(OutboxTarget.group) &
                row.targetId.equals(groupId)) |
            (row.target.equalsValue(OutboxTarget.member) &
                row.targetId.isInQuery(memberIds)) |
            (row.target.equalsValue(OutboxTarget.entry) &
                row.targetId.isInQuery(entryIds)),
      ))
      .go();
  // Foreign-key cascades remove entries, splits, conflicts, events and cursor.
  await (db.delete(db.groups)..where((row) => row.id.equals(groupId))).go();
}
