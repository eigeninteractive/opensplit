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
/// Read-only on the client. Every row is written by a trigger on the server and
/// arrives by sync — there is no local write path, because a record of what
/// happened that a device can author is not a record of what happened.
@freezed
abstract class EntryEvent with _$EntryEvent {
  const factory EntryEvent({
    required String id,
    required String entryId,
    required String groupId,

    /// The member who did it, not the account: a placeholder's edits survive
    /// them claiming an account later.
    required String actorId,
    required EntryEventKind kind,
    required DateTime createdAt,

    /// Empty for anything but an edit.
    @Default(<FieldChange>[]) List<FieldChange> changes,
  }) = _EntryEvent;
}
