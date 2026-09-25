//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'member_update.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MemberUpdate {
  /// Returns a new [MemberUpdate] instance.
  MemberUpdate({
    required this.displayName,

    required this.upiVpa,

    required this.leftAt,
  });

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @JsonKey(name: r'upiVpa', required: true, includeIfNull: true)
  final String? upiVpa;

  @JsonKey(name: r'leftAt', required: true, includeIfNull: true)
  final DateTime? leftAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberUpdate &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.leftAt == leftAt;

  @override
  int get hashCode =>
      displayName.hashCode +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      (leftAt == null ? 0 : leftAt.hashCode);

  factory MemberUpdate.fromJson(Map<String, dynamic> json) =>
      _$MemberUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$MemberUpdateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
