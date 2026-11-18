//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/reminder_outcome.dart';
import 'package:json_annotation/json_annotation.dart';

part 'reminder.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Reminder {
  /// Returns a new [Reminder] instance.
  Reminder({required this.outcome, required this.sentAt});

  @JsonKey(
    name: r'outcome',
    required: true,
    includeIfNull: false,
    unknownEnumValue: ReminderOutcome.unknownDefaultOpenApi,
  )
  final ReminderOutcome outcome;

  @JsonKey(name: r'sentAt', required: true, includeIfNull: true)
  final DateTime? sentAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Reminder && other.outcome == outcome && other.sentAt == sentAt;

  @override
  int get hashCode => outcome.hashCode + (sentAt == null ? 0 : sentAt.hashCode);

  factory Reminder.fromJson(Map<String, dynamic> json) =>
      _$ReminderFromJson(json);

  Map<String, dynamic> toJson() => _$ReminderToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
