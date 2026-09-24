//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'profile_update.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfileUpdate {
  /// Returns a new [ProfileUpdate] instance.
  ProfileUpdate({required this.displayName, required this.upiVpa});

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileUpdate &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa;

  @override
  int get hashCode =>
      (displayName == null ? 0 : displayName.hashCode) +
      (upiVpa == null ? 0 : upiVpa.hashCode);

  factory ProfileUpdate.fromJson(Map<String, dynamic> json) =>
      _$ProfileUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
