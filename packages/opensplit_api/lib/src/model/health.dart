//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'health.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Health {
  /// Returns a new [Health] instance.
  Health({required this.ok, required this.service, required this.now});

  @JsonKey(name: r'ok', required: true, includeIfNull: false)
  final bool ok;

  @JsonKey(
    name: r'service',
    required: true,
    includeIfNull: false,
    unknownEnumValue: HealthServiceEnum.unknownDefaultOpenApi,
  )
  final HealthServiceEnum service;

  @JsonKey(name: r'now', required: true, includeIfNull: false)
  final DateTime now;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Health &&
          other.ok == ok &&
          other.service == service &&
          other.now == now;

  @override
  int get hashCode => ok.hashCode + service.hashCode + now.hashCode;

  factory Health.fromJson(Map<String, dynamic> json) => _$HealthFromJson(json);

  Map<String, dynamic> toJson() => _$HealthToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum HealthServiceEnum {
  @JsonValue(r'opensplit')
  opensplit(r'opensplit'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const HealthServiceEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
