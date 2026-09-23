//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'member.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Member {
  /// Returns a new [Member] instance.
  Member({
    required this.id,

    required this.profileId,

    required this.displayName,

    required this.upiVpa,

    required this.joinedAt,

    required this.leftAt,

    required this.updatedAt,

    required this.seq,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'profileId', required: true, includeIfNull: true)
  final String? profileId;

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

  @JsonKey(name: r'joinedAt', required: true, includeIfNull: false)
  final DateTime joinedAt;

  @JsonKey(name: r'leftAt', required: true, includeIfNull: true)
  final DateTime? leftAt;

  @JsonKey(name: r'updatedAt', required: true, includeIfNull: false)
  final DateTime updatedAt;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Member &&
          other.id == id &&
          other.profileId == profileId &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.joinedAt == joinedAt &&
          other.leftAt == leftAt &&
          other.updatedAt == updatedAt &&
          other.seq == seq;

  @override
  int get hashCode =>
      id.hashCode +
      (profileId == null ? 0 : profileId.hashCode) +
      displayName.hashCode +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      joinedAt.hashCode +
      (leftAt == null ? 0 : leftAt.hashCode) +
      updatedAt.hashCode +
      seq.hashCode;

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);

  Map<String, dynamic> toJson() => _$MemberToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
