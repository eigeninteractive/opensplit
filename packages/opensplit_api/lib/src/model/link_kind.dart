//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum LinkKind {
  @JsonValue(r'invite')
  invite(r'invite'),
  @JsonValue(r'group_link')
  groupLink(r'group_link'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const LinkKind(this.value);

  final String value;

  @override
  String toString() => value;
}
