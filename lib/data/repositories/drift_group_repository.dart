import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/repositories/group_repository.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Local-first group and membership storage.
final class DriftGroupRepository implements GroupRepository {
  DriftGroupRepository(this._db, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
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

  @override
  Stream<Group?> watchGroup(String groupId) =>
      (_db.select(_db.groups)..where((t) => t.id.equals(groupId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  @override
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

  @override
  Future<Group?> getGroup(String groupId) async {
    final row = await (_db.select(
      _db.groups,
    )..where((t) => t.id.equals(groupId))).getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<List<Member>> getMembers(String groupId) async {
    final rows = await (_db.select(_db.members)
          ..where((t) => t.groupId.equals(groupId) & t.leftAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]))
        .get();
    return [for (final row in rows) row.toDomain()];
  }

  @override
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
      // `createdBy` is a profile id, which an anonymous local-only user does not
      // have yet. Falling back to the owner member id keeps the column
      // populated and is corrected when the account is linked.
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
            ),
          );
    });

    return (group: group.copyWith(createdBy: ownerProfileId ?? owner.id), owner: owner);
  }

  @override
  Future<void> updateGroup(Group group) async {
    await (_db.update(_db.groups)..where((t) => t.id.equals(group.id))).write(
      GroupsCompanion(
        name: Value(group.name),
        defaultCurrency: Value(group.defaultCurrency),
        simplifyDebts: Value(group.simplifyDebts),
        archivedAt: Value(group.archivedAt),
      ),
    );
  }

  @override
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
          ),
        );
    return member;
  }

  @override
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
      MembersCompanion(displayName: Value(trimmed)),
    );
  }

  @override
  Future<void> removeMember(String memberId) async {
    // Marked as left, never deleted. Their name still has to render on every
    // expense they were part of, and their balance still has to be settleable.
    await (_db.update(_db.members)..where((t) => t.id.equals(memberId))).write(
      MembersCompanion(leftAt: Value(_clock())),
    );
  }

  @override
  Future<void> setArchived(String groupId, {required bool archived}) async {
    await (_db.update(_db.groups)..where((t) => t.id.equals(groupId))).write(
      GroupsCompanion(archivedAt: Value(archived ? _clock() : null)),
    );
  }
}
