import 'package:drift/drift.dart';

import '../local/database.dart';

/// Checks membership at the write boundary, inside the caller's transaction.
///
/// A null account is a purely local ledger. Synced repositories always supply
/// their account, so a stale screen or direct route cannot bypass this rule.
Future<void> requireGroupWrite(
  AppDatabase db,
  String groupId,
  String? accountId,
) async {
  final group = await (db.select(
    db.groups,
  )..where((row) => row.id.equals(groupId))).getSingleOrNull();
  if (group == null) throw StateError('This group is not on this device.');
  if (accountId == null) return;
  final member =
      await (db.select(db.members)..where(
            (row) =>
                row.groupId.equals(groupId) &
                row.profileId.equals(accountId) &
                row.leftAt.isNull(),
          ))
          .getSingleOrNull();
  if (member == null) {
    throw StateError('You are no longer a member of this group.');
  }
}
