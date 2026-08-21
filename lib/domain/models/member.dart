import 'package:freezed_annotation/freezed_annotation.dart';

part 'member.freezed.dart';

/// A member's authority within a group.
enum MemberRole { owner, member }

/// A group-scoped identity — the load-bearing decision in this data model.
///
/// Members are not auth users. Every financial row references a member id, and
/// a member may have no account at all: `profileId == null` is a placeholder
/// like "Arun", added by a friend before Arun has ever heard of this app. He is
/// a first-class member immediately — he can be a payer, hold a balance, and be
/// settled with.
///
/// When Arun does sign up and claim his slot, exactly one column changes. If
/// entries referenced profile ids instead, every person joining a group would
/// require a data migration.
@freezed
abstract class Member with _$Member {
  const factory Member({
    required String id,
    required String groupId,

    /// Null while this member is a placeholder.
    String? profileId,
    required String displayName,
    @Default(MemberRole.member) MemberRole role,
    required DateTime joinedAt,

    /// Set when a member leaves. They are never deleted — a member with
    /// financial history has to stay referenceable for their past entries to
    /// make sense.
    DateTime? leftAt,

    /// A UPI handle for this member of this group.
    ///
    /// Group-scoped rather than on the profile, because a placeholder has no
    /// profile and settling with a placeholder is exactly when the handle is
    /// needed. Falls back to the linked profile's when null.
    String? upiVpa,

    /// Version for last-write-wins. See [Group.updatedAt].
    DateTime? updatedAt,
  }) = _Member;

  const Member._();

  /// True when nobody has claimed this member yet.
  bool get isPlaceholder => profileId == null;

  bool get isActive => leftAt == null;
}
