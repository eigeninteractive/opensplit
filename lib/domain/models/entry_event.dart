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
