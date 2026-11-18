//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum ReminderOutcome {
  @JsonValue(r'sent')
  sent(r'sent'),
  @JsonValue(r'already_reminded')
  alreadyReminded(r'already_reminded'),
  @JsonValue(r'unreachable')
  unreachable(r'unreachable'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const ReminderOutcome(this.value);

  final String value;

  @override
  String toString() => value;
}
