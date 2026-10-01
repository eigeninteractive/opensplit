//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'device_forgotten.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DeviceForgotten {
  /// Returns a new [DeviceForgotten] instance.
  DeviceForgotten({required this.forgotten});

  @JsonKey(name: r'forgotten', required: true, includeIfNull: false)
  final bool forgotten;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceForgotten && other.forgotten == forgotten;

  @override
  int get hashCode => forgotten.hashCode;

  factory DeviceForgotten.fromJson(Map<String, dynamic> json) =>
      _$DeviceForgottenFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceForgottenToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
