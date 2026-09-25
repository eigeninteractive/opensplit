import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../data/local/database.dart';
import 'entry_event.dart';
import 'kinds.dart';

export '../../data/local/database.dart' show GroupEventRow;
export 'kinds.dart' show EventKind;

/// Typed reads of a stored event's payload, whose shape [GroupEventRow.kind]
/// decides.
extension GroupEventPayload on GroupEventRow {
  /// The expense after-image of an [EventKind.entry] row.
  api.EntrySnapshot get snapshot => api.EntrySnapshot.fromJson(payload);

  /// The name a member or group event carries: `displayName` for a member,
  /// `name` for the group.
  String? get name =>
      payload['displayName'] as String? ?? payload['name'] as String?;

  /// What a rename renamed from.
  String? get previousName => payload['previousName'] as String?;
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

  final EventKind kind;
}
