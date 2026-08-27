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
/// Authored by the device that made the change, in the same transaction as the
/// change itself, and pushed like any other row. See `describeEntryWrite` for
/// why that replaced a server-side trigger, and what the server still
/// guarantees instead.
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
