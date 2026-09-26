//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/platform.dart';
import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Device {
  /// Returns a new [Device] instance.
  Device({required this.token, required this.platform});

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @JsonKey(
    name: r'platform',
    required: true,
    includeIfNull: false,
    unknownEnumValue: Platform.unknownDefaultOpenApi,
  )
  final Platform platform;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device && other.token == token && other.platform == platform;

  @override
  int get hashCode => token.hashCode + platform.hashCode;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
