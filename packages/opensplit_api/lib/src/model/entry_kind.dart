//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum EntryKind {
  @JsonValue(r'expense')
  expense(r'expense'),
  @JsonValue(r'settlement')
  settlement(r'settlement'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const EntryKind(this.value);

  final String value;

  @override
  String toString() => value;
}
