import '../models/group.dart';
import '../models/member.dart';

/// Reads and writes groups and their membership.
///
/// The interface lives in `domain/` and knows nothing about Drift, Supabase or
/// HTTP. That is not ceremony: it is the mechanism behind the self-hosting
/// promise and the exit route if the hosted backend's pricing moves. Swapping
/// the storage layer must not require touching a single screen.
abstract interface class GroupRepository {
  /// Groups this user belongs to, newest activity first.
  ///
  /// A stream rather than a future because every screen is driven by the local
  /// database: a sync that lands in the background updates the UI without any
  /// screen having to know a sync happened.
  Stream<List<Group>> watchGroups({bool includeArchived = false});

  Stream<Group?> watchGroup(String groupId);

  /// Members of a group, including placeholders and people who have left.
  Stream<List<Member>> watchMembers(String groupId, {bool includeLeft = false});

  Future<Group?> getGroup(String groupId);

  Future<List<Member>> getMembers(String groupId);

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
  });

  Future<void> updateGroup(Group group);

  /// Adds a member. A null [profileId] creates a placeholder — someone who is
  /// fully participating in the group's finances without having an account.
  Future<Member> addMember(
    String groupId, {
    required String displayName,
    String? profileId,
  });

  Future<void> renameMember(String memberId, String displayName);

  /// Marks a member as having left. Never deletes: their past entries have to
  /// keep making sense.
  Future<void> removeMember(String memberId);

  /// Records a UPI handle against a member of a group.
  ///
  /// Group-scoped rather than on the profile, so a placeholder — someone who
  /// has never opened the app — can still be paid. Pass null to clear it.
  Future<void> setMemberUpiVpa(String memberId, String? vpa);

  Future<void> setArchived(String groupId, {required bool archived});
}
