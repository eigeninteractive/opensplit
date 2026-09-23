//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum SplitKind {
  @JsonValue(r'equal')
  equal(r'equal'),
  @JsonValue(r'exact')
  exact(r'exact'),
  @JsonValue(r'shares')
  shares(r'shares'),
  @JsonValue(r'percent')
  percent(r'percent'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const SplitKind(this.value);

  final String value;

  @override
  String toString() => value;
}
