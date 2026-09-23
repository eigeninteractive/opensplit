//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// stale: re-read, re-compose and send again. permanent: this will be refused identically forever; do not retry. transient: back off and try the same request again.
enum Retry {
  @JsonValue(r'stale')
  stale(r'stale'),
  @JsonValue(r'permanent')
  permanent(r'permanent'),
  @JsonValue(r'transient')
  transient(r'transient'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const Retry(this.value);

  final String value;

  @override
  String toString() => value;
}
