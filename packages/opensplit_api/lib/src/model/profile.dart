//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'profile.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Profile {
  /// Returns a new [Profile] instance.
  Profile({
    required this.id,

    required this.displayName,

    required this.upiVpa,

    required this.updatedAt,

    required this.deletedAt,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

  @JsonKey(name: r'updatedAt', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @JsonKey(name: r'deletedAt', required: true, includeIfNull: true)
  final DateTime? deletedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          other.id == id &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode =>
      id.hashCode +
      (displayName == null ? 0 : displayName.hashCode) +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      updatedAt.hashCode +
      (deletedAt == null ? 0 : deletedAt.hashCode);

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
