import 'entry_event.dart';
import 'kinds.dart';

export '../../data/local/database.dart' show GroupEventRow;
export 'kinds.dart' show EventKind;

/// A line in a group's activity feed.
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

  /// The member who did it, not the account: a placeholder's edits survive them
  /// claiming an account later.
  final String? actorId;

  final DateTime createdAt;

  /// This device's own account of a change it has not yet managed to push.
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
  final EventKind kind;

  final String displayName;

  /// Only ever set on [EventKind.memberRenamed], where it is the whole
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

  final EventKind kind;
  final String name;
  final String? previousName;
}

/// An invite link was minted or destroyed.
final class LinkChanged extends GroupEvent {
  const LinkChanged({
    required super.id,
    required super.groupId,
    required super.actorId,
    required super.createdAt,
    super.isProvisional = false,
    required this.kind,
  });

  final EventKind kind;
}
