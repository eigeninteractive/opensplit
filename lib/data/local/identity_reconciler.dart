import 'package:drift/drift.dart';

import '../sync/outbox_queue.dart';
import 'database.dart';

/// Repoints everything this device recorded under a locally invented identity
/// at the real account id.
///
/// Before any backend exists the app still needs to know which member is "you",
/// so it generates a local uuid and writes it to `members.profile_id` exactly
/// as a real account id would be. When a session finally arrives, those
/// references have to move.
///
/// This is the whole payoff of members being group-scoped rather than auth
/// users: it is an UPDATE over one column. No entry, payer or share row is
/// touched, and no balance moves, because none of them ever referenced a
/// profile in the first place. Had financial rows pointed at profiles, this
/// would be a data migration every time anyone signed in.
///
/// Affected rows are re-queued afterwards, since their new contents have to
/// reach the server.
Future<void> adoptAuthIdentity(
  AppDatabase db, {
  required String localProfileId,
  required String authUserId,
  OutboxQueue? outbox,
}) async {
  if (localProfileId == authUserId || localProfileId.isEmpty) return;

  final movedMembers = <String>[];
  final movedGroups = <String>[];

  await db.transaction(() async {
    final members = await (db.select(
      db.members,
    )..where((t) => t.profileId.equals(localProfileId))).get();
    final groups = await (db.select(
      db.groups,
    )..where((t) => t.createdBy.equals(localProfileId))).get();

    movedMembers.addAll(members.map((m) => m.id));
    movedGroups.addAll(groups.map((g) => g.id));

    await (db.update(db.members)
          ..where((t) => t.profileId.equals(localProfileId)))
        .write(MembersCompanion(profileId: Value(authUserId)));
    await (db.update(db.groups)
          ..where((t) => t.createdBy.equals(localProfileId)))
        .write(GroupsCompanion(createdBy: Value(authUserId)));

    // The profile row is keyed by id, so it is recreated rather than updated.
    // The server already has one for this account, created by the
    // handle_new_user trigger; this keeps the local cache in step.
    final existing = await (db.select(
      db.profiles,
    )..where((t) => t.id.equals(localProfileId))).getSingleOrNull();
    if (existing != null) {
      await db
          .into(db.profiles)
          .insertOnConflictUpdate(
            ProfilesCompanion.insert(
              id: authUserId,
              displayName: existing.displayName,
              avatarUrl: Value(existing.avatarUrl),
              upiVpa: Value(existing.upiVpa),
            ),
          );
      await (db.delete(
        db.profiles,
      )..where((t) => t.id.equals(localProfileId))).go();
    }
  });

  for (final id in movedGroups) {
    await outbox?.enqueue(OutboxTarget.group, id);
  }
  for (final id in movedMembers) {
    await outbox?.enqueue(OutboxTarget.member, id);
  }
}
