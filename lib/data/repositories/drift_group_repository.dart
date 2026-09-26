import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/settle/upi.dart';
import '../local/database.dart';
import '../sync/outbox_queue.dart';

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
  Stream<List<Group>> watchGroups({bool includeArchived = false}) {
    final query = _db.select(_db.groups)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    return query.watch().map((rows) => [for (final row in rows) row]);
  }

  Stream<Group?> watchGroup(String groupId) => (_db.select(
    _db.groups,
  )..where((t) => t.id.equals(groupId))).watchSingleOrNull().map((row) => row);

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
    return query.watch().map((rows) => [for (final row in rows) row]);
  }

  Future<Group?> getGroup(String groupId) async {
    final row = await (_db.select(
      _db.groups,
    )..where((t) => t.id.equals(groupId))).getSingleOrNull();
    return row;
  }

  Future<List<Member>> getMembers(String groupId) async {
    final rows =
        await (_db.select(_db.members)
              ..where((t) => t.groupId.equals(groupId) & t.leftAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]))
            .get();
    return [for (final row in rows) row];
  }

  /// Creates a group along with its first member — whoever made it.
  Future<({Group group, Member creator})> createGroup({
    required String name,
    required String defaultCurrency,
    required String creatorDisplayName,
    String? creatorProfileId,
    bool isDirect = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A group needs a name.');
    }

    final now = _clock();
    final creator = Member(
      id: _uuid.v4(),
      groupId: _uuid.v4(),
      profileId: creatorProfileId,
      displayName: creatorDisplayName.trim(),
      joinedAt: now,
    );
    final group = Group(
      id: creator.groupId,
      name: trimmed,
      defaultCurrency: defaultCurrency,
      isDirect: isDirect,
      simplifyDebts: true,
      createdBy: creator.id,
      createdAt: now,
    );

    await _db.transaction(() async {
      await _db.into(_db.groups).insert(group);
      await _db.into(_db.members).insert(creator);
      // Both rows have to reach the server, and the group has to land first:
      // members and entries reference it by foreign key.
      await outbox?.enqueue(OutboxTarget.group, group.id);
      await outbox?.enqueue(OutboxTarget.member, creator.id);
    });

    return (group: group, creator: creator);
  }

  /// Writes a group's editable fields.
  Future<void> updateGroup(Group group) async {
    final trimmed = group.name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(group.name, 'name', 'A group needs a name.');
    }

    await _db.transaction(() async {
      await (_db.update(_db.groups)..where((t) => t.id.equals(group.id))).write(
        GroupsCompanion(
          name: Value(trimmed),
          simplifyDebts: Value(group.simplifyDebts),
          archivedAt: Value(group.archivedAt),
          // Bumped on every local write.
        ),
      );
      await outbox?.enqueue(OutboxTarget.group, group.id);
    });
  }

  /// Leaves a group: marks your own member row as having left, and archives the
  /// group on this device.
  Future<void> leaveGroup({
    required String groupId,
    required String memberId,
  }) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(_db.members)..where((t) => t.id.equals(memberId)))
          .write(MembersCompanion(leftAt: Value(now)));
      await (_db.update(_db.groups)..where((t) => t.id.equals(groupId))).write(
        GroupsCompanion(archivedAt: Value(now)),
      );
      await outbox?.enqueue(OutboxTarget.member, memberId);
    });
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
    // app.
    final member = Member(
      id: _uuid.v4(),
      groupId: groupId,
      profileId: profileId,
      displayName: trimmed,
      joinedAt: _clock(),
    );

    await _db.transaction(() async {
      await _db.into(_db.members).insert(member);
      await outbox?.enqueue(OutboxTarget.member, member.id);
    });
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
    await _db.transaction(() async {
      await (_db.update(_db.members)..where((t) => t.id.equals(memberId)))
          .write(MembersCompanion(displayName: Value(trimmed)));
      await outbox?.enqueue(OutboxTarget.member, memberId);
    });
  }

  /// Marks a member as having left. Never deletes: their past entries have to
  /// keep making sense.
  Future<void> removeMember(String memberId) async {
    // Marked as left, never deleted. Their name still has to render on every
    // expense they were part of, and their balance still has to be settleable.
    await _db.transaction(() async {
      await (_db.update(_db.members)..where((t) => t.id.equals(memberId)))
          .write(MembersCompanion(leftAt: Value(_clock())));
      await outbox?.enqueue(OutboxTarget.member, memberId);
    });
  }

  /// Records a UPI handle against a member of a group.
  Future<void> setMemberUpiVpa(String memberId, String? vpa) async {
    final trimmed = vpa?.trim();
    if (trimmed != null && trimmed.isNotEmpty && !isValidUpiVpa(trimmed)) {
      throw ArgumentError.value(vpa, 'vpa', 'Not a UPI ID.');
    }
    await _db.transaction(() async {
      await (_db.update(
        _db.members,
      )..where((t) => t.id.equals(memberId))).write(
        MembersCompanion(
          upiVpa: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        ),
      );
      await outbox?.enqueue(OutboxTarget.member, memberId);
    });
  }

  /// How this account's groups would fare if the account were deleted.
  Future<({int solo, int shared})> membershipBreakdown(String profileId) async {
    final rows = await _db.select(_db.members).get();

    final byGroup = <String, List<Member>>{};
    for (final row in rows) {
      byGroup.putIfAbsent(row.groupId, () => []).add(row);
    }

    var solo = 0;
    var shared = 0;
    for (final members in byGroup.values) {
      if (!members.any((m) => m.profileId == profileId)) continue;
      final others = members.any(
        (m) => m.profileId != null && m.profileId != profileId,
      );
      if (others) {
        shared++;
      } else {
        solo++;
      }
    }
    return (solo: solo, shared: shared);
  }

  Future<void> setArchived(String groupId, {required bool archived}) async {
    await (_db.update(_db.groups)..where((t) => t.id.equals(groupId))).write(
      GroupsCompanion(archivedAt: Value(archived ? _clock() : null)),
    );
    await outbox?.enqueue(OutboxTarget.group, groupId);
  }
}
