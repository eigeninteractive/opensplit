import 'package:freezed_annotation/freezed_annotation.dart';

part 'entry_event.freezed.dart';

/// What happened to an expense.
enum EntryEventKind { created, edited, deleted, restored }

/// One field that changed, and what it changed from and to.
///
/// Values are kept as strings rather than parsed into their real types. An
/// activity feed renders them; nothing computes with them, and a diff row that
/// tried to be typed would need a variant per column for no gain.
@freezed
abstract class FieldChange with _$FieldChange {
  const factory FieldChange({required String field, String? from, String? to}) =
      _FieldChange;
}

/// A line in a group's activity feed.
///
/// Derived, never stored and never sent. What is stored is a chain of
/// [EntrySnapshot]s, each recording what an expense looked like after a change;
/// this is the difference between two of them, computed on read by
/// `describeSnapshot`.
///
/// Keeping it as its own type is what let the storage change underneath the
/// feed without the screens noticing: nothing that renders activity knows
/// whether the line it is showing came from the server's record or from this
/// device's provisional one.
@freezed
abstract class EntryEvent with _$EntryEvent {
  const factory EntryEvent({
    required String id,
    required String entryId,
    required String groupId,

    /// The member who did it, not the account: a placeholder's edits survive
    /// them claiming an account later.
    ///
    /// Null when the change came from something with no member row. Rendered
    /// as "someone" rather than hidden -- an unattributable change still
    /// belongs on the record.
    required String? actorId,
    required EntryEventKind kind,
    required DateTime createdAt,

    /// Empty for anything but an edit.
    @Default(<FieldChange>[]) List<FieldChange> changes,

    /// This device's own account of a change it has not yet managed to push.
    ///
    /// Replaced by the server's the moment one arrives. Worth surfacing: until
    /// then the line describes something no one else in the group can see.
    @Default(false) bool isProvisional,
  }) = _EntryEvent;
}
