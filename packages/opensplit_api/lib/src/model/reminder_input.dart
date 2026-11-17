//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'reminder_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReminderInput {
  /// Returns a new [ReminderInput] instance.
  ReminderInput({required this.memberId, required this.currency});

  @JsonKey(name: r'memberId', required: true, includeIfNull: false)
  final String memberId;

  @JsonKey(name: r'currency', required: true, includeIfNull: false)
  final String currency;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderInput &&
          other.memberId == memberId &&
          other.currency == currency;

  @override
  int get hashCode => memberId.hashCode + currency.hashCode;

  factory ReminderInput.fromJson(Map<String, dynamic> json) =>
      _$ReminderInputFromJson(json);

  Map<String, dynamic> toJson() => _$ReminderInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
