//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'bootstrap.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Bootstrap {
  /// Returns a new [Bootstrap] instance.
  Bootstrap({
    required this.profileId,

    required this.displayName,

    required this.upiVpa,

    required this.isAnonymous,

    required this.groupIds,
  });

  @JsonKey(name: r'profileId', required: true, includeIfNull: false)
  final String profileId;

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

  @JsonKey(name: r'isAnonymous', required: true, includeIfNull: false)
  final bool isAnonymous;

  @JsonKey(name: r'groupIds', required: true, includeIfNull: false)
  final List<String> groupIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bootstrap &&
          other.profileId == profileId &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.isAnonymous == isAnonymous &&
          other.groupIds == groupIds;

  @override
  int get hashCode =>
      profileId.hashCode +
      (displayName == null ? 0 : displayName.hashCode) +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      isAnonymous.hashCode +
      groupIds.hashCode;

  factory Bootstrap.fromJson(Map<String, dynamic> json) =>
      _$BootstrapFromJson(json);

  Map<String, dynamic> toJson() => _$BootstrapToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
