import 'package:freezed_annotation/freezed_annotation.dart';

import 'entry_event.dart';
import 'entry_snapshot.dart';

part 'group_event.freezed.dart';

/// Everything a group can be told happened to it.
///
/// One enum rather than one table per kind, because the whole point of the
/// record is that it is a single ordered account of a group's life. A reader
/// wants "what happened here, in order", and that question should not need a
/// join per thing that can happen.
///
/// The names are the server's `group_event_kind` values verbatim. They are
/// parsed off the wire and out of the local column by name, so renaming one
/// here without renaming it in the migration would go unnoticed until a device
/// met a row it could not read — which is what [GroupEventKind.parse] exists to
/// make survivable.
enum GroupEventKind {
  /// An expense, as it stood after a change. The only kind whose detail has to
  /// be worked out by comparing two rows, because the server cannot see an
  /// expense's before-image at the only moment it could record one.
  entry,

  memberAdded,
  memberJoined,
  memberLeft,
  memberRenamed,

  groupRenamed,
  groupArchived,
  groupRestored,

  linkCreated,
  linkRevoked;

  /// `member_joined` and friends, as the database spells them.
  String get wireName => switch (this) {
    GroupEventKind.entry => 'entry',
    GroupEventKind.memberAdded => 'member_added',
    GroupEventKind.memberJoined => 'member_joined',
    GroupEventKind.memberLeft => 'member_left',
    GroupEventKind.memberRenamed => 'member_renamed',
    GroupEventKind.groupRenamed => 'group_renamed',
    GroupEventKind.groupArchived => 'group_archived',
    GroupEventKind.groupRestored => 'group_restored',
    GroupEventKind.linkCreated => 'link_created',
    GroupEventKind.linkRevoked => 'link_revoked',
  };

  /// Null for a name this build has never heard of.
  ///
  /// Which is a state worth having rather than a crash. A server that has
  /// learned a new kind will send it to clients that have not, and the right
  /// answer for an old build is to leave that line out of the feed — not to
  /// fail the whole sync page it arrived in and stop the feed updating at all.
  static GroupEventKind? parse(String wire) {
    for (final kind in GroupEventKind.values) {
      if (kind.wireName == wire) return kind;
    }
    return null;
  }
}

/// One row of the record, exactly as it is stored.
///
/// The raw material. [GroupEvent] is what a screen renders, and the two are
/// deliberately different types: a row is what the server committed, a feed
/// line is what a reader is told, and for expenses the second takes two of the
/// first to produce.
@freezed
abstract class GroupEventRow with _$GroupEventRow {
  const factory GroupEventRow({
    required String id,
    required String groupId,

    /// The member who did it, not the account: authorship is group-scoped, so
    /// a placeholder's edits survive them claiming an account.
    ///
    /// Null when nobody can be named — which for a join is the ordinary case
    /// rather than a failure, since the person arriving has no member row until
    /// the statement that creates it commits.
    required String? actorId,
    required DateTime createdAt,
    required GroupEventKind kind,

    /// The entry, member or invite token this is about. Null for the kinds
    /// whose subject is the group itself.
    String? subjectId,

    /// The after-image, in whatever shape [kind] calls for. Parsed by the
    /// readers below rather than up front, because only one kind's payload is
    /// ever wanted at a time.
    required Map<String, Object?> payload,

    /// Written by this device and not yet replaced by the server's account of
    /// the same change. Local only; there is no such column on the server.
    @Default(false) bool isProvisional,
  }) = _GroupEventRow;

  const GroupEventRow._();

  /// The expense snapshot inside an `entry` row.
  ///
  /// Throws for any other kind, which is a programming error rather than a
  /// data one: the callers all switch on [kind] first.
  EntrySnapshot get snapshot => snapshotFromPayload(
    id: id,
    entryId: subjectId!,
    groupId: groupId,
    actorId: actorId,
    createdAt: createdAt,
    payload: payload,
    isProvisional: isProvisional,
  );

  /// The name carried by a member or group event.
  String? get name =>
      payload['display_name'] as String? ?? payload['name'] as String?;

  /// What a rename renamed from.
  String? get previousName => payload['previous_name'] as String?;
}

/// A line in a group's activity feed.
///
/// Sealed rather than one shape with a kind field, so that a screen rendering
/// the feed has to say what it does with every kind and the compiler checks it
/// did. Adding a variant here is what makes every `switch` over it fail to
/// compile until it has been thought about — which is the property that was
/// missing when the feed could only describe expenses and a member joining had
/// nowhere to go.
///
/// Derived, never stored and never sent. What is stored is [GroupEventRow]s;
/// this is what a reader is told, and for expenses producing one takes two of
/// them.
///
/// Keeping it as its own type is what let the storage change underneath the
/// feed without the screens noticing: nothing that renders activity knows
/// whether the line it is showing came from the server's record or from this
/// device's provisional one.
sealed class GroupEvent {
  const GroupEvent({
    required this.id,
    required this.groupId,
    required this.actorId,
    required this.createdAt,
    required this.isProvisional,
  });

  final String id;
  final String groupId;

  /// The member who did it, not the account: a placeholder's edits survive
  /// them claiming an account later.
  ///
  /// Null when the change came from something with no member row. Rendered as
  /// "someone" rather than hidden — an unattributable change still belongs on
  /// the record.
  final String? actorId;

  final DateTime createdAt;

  /// This device's own account of a change it has not yet managed to push.
  ///
  /// Replaced by the server's the moment one arrives. Worth surfacing: until
  /// then the line describes something no one else in the group can see.
  final bool isProvisional;
}

/// Something happened to an expense.
final class EntryChanged extends GroupEvent {
  const EntryChanged({
    required super.id,
    required super.groupId,
    required super.actorId,
    required super.createdAt,
    super.isProvisional = false,
    required this.entryId,
    required this.kind,
    this.changes = const <FieldChange>[],
  });

  final String entryId;
  final EntryEventKind kind;

  /// Empty for anything but an edit.
  final List<FieldChange> changes;
}

/// Somebody arrived, left, was added or was renamed.
final class MemberChanged extends GroupEvent {
  const MemberChanged({
    required super.id,
    required super.groupId,
    required super.actorId,
    required super.createdAt,
    super.isProvisional = false,
    required this.memberId,
    required this.kind,
    required this.displayName,
    this.previousName,
  });

  final String memberId;

  /// One of the `member*` kinds. Narrowed by construction rather than by type:
  /// a separate enum per variant would be four enums that all have to be kept
  /// in step with one migration.
  final GroupEventKind kind;

  final String displayName;

  /// Only ever set on [GroupEventKind.memberRenamed], where it is the whole
  /// meaning of the line.
  final String? previousName;
}

/// The group itself was renamed, archived or restored.
final class GroupChanged extends GroupEvent {
  const GroupChanged({
    required super.id,
    required super.groupId,
    required super.actorId,
    required super.createdAt,
    super.isProvisional = false,
    required this.kind,
    required this.name,
    this.previousName,
  });

  final GroupEventKind kind;
  final String name;
  final String? previousName;
}

/// An invite link was minted or destroyed.
///
/// On the record because an open link is bearer authority over membership: it
/// is the one object here that lets somebody nobody invited personally walk in,
/// so the group is entitled to see it appear and disappear.
final class LinkChanged extends GroupEvent {
  const LinkChanged({
    required super.id,
    required super.groupId,
    required super.actorId,
    required super.createdAt,
    super.isProvisional = false,
    required this.kind,
  });

  final GroupEventKind kind;
}
