import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/group.dart';
import '../../domain/settle/upi.dart';
import '../../domain/models/member.dart';
import '../local/database.dart';
import '../sync/outbox_queue.dart';
import 'mappers.dart';

/// Local-first group and membership storage.
final class DriftGroupRepository {
  DriftGroupRepository(
    this._db, {
    this.outbox,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// Null in a purely local build, where there is nothing to sync to.
  final OutboxQueue? outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Groups this user belongs to, newest activity first.
  ///
  /// A stream rather than a future because every screen is driven by the local
  /// database: a sync that lands in the background updates the UI without any
  /// screen having to know a sync happened.
  Stream<List<Group>> watchGroups({bool includeArchived = false}) {
    final query = _db.select(_db.groups)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    return query.watch().map(
      (rows) => [for (final row in rows) row.toDomain()],
    );
  }

  Stream<Group?> watchGroup(String groupId) =>
      (_db.select(_db.groups)..where((t) => t.id.equals(groupId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  /// Members of a group, including placeholders and people who have left.
  Stream<List<Member>> watchMembers(
    String groupId, {
    bool includeLeft = false,
  }) {
    final query = _db.select(_db.members)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]);
    if (!includeLeft) {
      query.where((t) => t.leftAt.isNull());
    }
    return query.watch().map(
      (rows) => [for (final row in rows) row.toDomain()],
    );
  }

  Future<Group?> getGroup(String groupId) async {
    final row = await (_db.select(
      _db.groups,
    )..where((t) => t.id.equals(groupId))).getSingleOrNull();
    return row?.toDomain();
  }

  Future<List<Member>> getMembers(String groupId) async {
    final rows =
        await (_db.select(_db.members)
              ..where((t) => t.groupId.equals(groupId) & t.leftAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]))
            .get();
    return [for (final row in rows) row.toDomain()];
  }

  /// Creates a group along with its first member — the creator, as owner.
  ///
  /// One operation because a group with no members is not a valid state; it
  /// would render as an empty screen with no way to add an expense.
  Future<({Group group, Member owner})> createGroup({
    required String name,
    required String defaultCurrency,
    required String ownerDisplayName,
    String? ownerProfileId,
    bool isDirect = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A group needs a name.');
    }

    final now = _clock();
    final group = Group(
      id: _uuid.v4(),
      name: trimmed,
      defaultCurrency: defaultCurrency,
      isDirect: isDirect,
      // `createdBy` is a profile id, which an anonymous local-only user
      // does not have yet. Falling back to the owner member id keeps the
      // column populated and is corrected when the account is linked.
      createdBy: ownerProfileId ?? '',
      createdAt: now,
    );
    final owner = Member(
      id: _uuid.v4(),
      groupId: group.id,
      profileId: ownerProfileId,
      displayName: ownerDisplayName.trim(),
      role: MemberRole.owner,
      joinedAt: now,
    );

    await _db.transaction(() async {
      await _db
          .into(_db.groups)
          .insert(
            GroupsCompanion.insert(
              id: group.id,
              name: group.name,
              defaultCurrency: group.defaultCurrency,
              isDirect: Value(group.isDirect),
              simplifyDebts: Value(group.simplifyDebts),
              createdBy: ownerProfileId ?? owner.id,
              createdAt: group.createdAt,
              updatedAt: Value(now),
            ),
          );
      await _db
          .into(_db.members)
          .insert(
            MembersCompanion.insert(
              id: owner.id,
              groupId: group.id,
              profileId: Value(owner.profileId),
              displayName: owner.displayName,
              role: owner.role,
              joinedAt: owner.joinedAt,
              updatedAt: Value(now),
            ),
          );
    });

    // Both rows have to reach the server, and the group has to land first:
    // members and entries reference it by foreign key.
    await outbox?.enqueue(OutboxTarget.group, group.id);
    await outbox?.enqueue(OutboxTarget.member, owner.id);

    return (
      group: group.copyWith(createdBy: ownerProfileId ?? owner.id),
      owner: owner,
    );
  }

  Future<void> updateGroup(Group group) async {
    await (_db.update(_db.groups)..where((t) => t.id.equals(group.id))).write(
      GroupsCompanion(
        name: Value(group.name),
        defaultCurrency: Value(group.defaultCurrency),
        simplifyDebts: Value(group.simplifyDebts),
        archivedAt: Value(group.archivedAt),
        // Bumped on every local write. Without this a rename made offline
        // keeps its old version, and the next pull sees the server as newer
        // and discards the edit before the outbox has had a chance to send it.
        updatedAt: Value(_clock()),
      ),
    );
    await outbox?.enqueue(OutboxTarget.group, group.id);
  }

  /// Adds a member. A null [profileId] creates a placeholder — someone who is
  /// fully participating in the group's finances without having an account.
  Future<Member> addMember(
    String groupId, {
    required String displayName,
    String? profileId,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'A member needs a name.',
      );
    }

    // A placeholder — profileId null — is a full member from this moment: they
    // can pay, owe and be settled with, all before they have ever heard of the
    // app. That is the entire point of members being group-scoped.
    final member = Member(
      id: _uuid.v4(),
      groupId: groupId,
      profileId: profileId,
      displayName: trimmed,
      joinedAt: _clock(),
    );

    await _db
        .into(_db.members)
        .insert(
          MembersCompanion.insert(
            id: member.id,
            groupId: member.groupId,
            profileId: Value(member.profileId),
            displayName: member.displayName,
            role: member.role,
            joinedAt: member.joinedAt,
            updatedAt: Value(member.joinedAt),
          ),
        );
    await outbox?.enqueue(OutboxTarget.member, member.id);
    return member;
  }

  Future<void> renameMember(String memberId, String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'A member needs a name.',
      );
    }
    await (_db.update(_db.members)..where((t) => t.id.equals(memberId))).write(
      MembersCompanion(displayName: Value(trimmed), updatedAt: Value(_clock())),
    );
    await outbox?.enqueue(OutboxTarget.member, memberId);
  }

  /// Marks a member as having left. Never deletes: their past entries have to
  /// keep making sense.
  Future<void> removeMember(String memberId) async {
    // Marked as left, never deleted. Their name still has to render on every
    // expense they were part of, and their balance still has to be settleable.
    await (_db.update(_db.members)..where((t) => t.id.equals(memberId))).write(
      MembersCompanion(leftAt: Value(_clock()), updatedAt: Value(_clock())),
    );
    await outbox?.enqueue(OutboxTarget.member, memberId);
  }

  /// Records a UPI handle against a member of a group.
  ///
  /// Group-scoped rather than on the profile, so a placeholder — someone who
  /// has never opened the app — can still be paid. Pass null to clear it.
  Future<void> setMemberUpiVpa(String memberId, String? vpa) async {
    final trimmed = vpa?.trim();
    if (trimmed != null && trimmed.isNotEmpty && !isValidUpiVpa(trimmed)) {
      throw ArgumentError.value(vpa, 'vpa', 'Not a UPI ID.');
    }
    await (_db.update(_db.members)..where((t) => t.id.equals(memberId))).write(
      MembersCompanion(
        upiVpa: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        updatedAt: Value(_clock()),
      ),
    );
    await outbox?.enqueue(OutboxTarget.member, memberId);
  }

  Future<void> setArchived(String groupId, {required bool archived}) async {
    await (_db.update(_db.groups)..where((t) => t.id.equals(groupId))).write(
      GroupsCompanion(
        archivedAt: Value(archived ? _clock() : null),
        updatedAt: Value(_clock()),
      ),
    );
    await outbox?.enqueue(OutboxTarget.group, groupId);
  }
}
