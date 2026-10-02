//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum AvatarKind {
  @JsonValue(r'initials')
  initials(r'initials'),
  @JsonValue(r'emoji')
  emoji(r'emoji'),
  @JsonValue(r'icon')
  icon(r'icon'),
  @JsonValue(r'photo')
  photo(r'photo'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const AvatarKind(this.value);

  final String value;

  @override
  String toString() => value;
}
