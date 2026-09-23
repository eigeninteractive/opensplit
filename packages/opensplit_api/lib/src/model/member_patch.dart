//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'member_patch.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MemberPatch {
  /// Returns a new [MemberPatch] instance.
  MemberPatch({this.displayName, this.upiVpa, this.leftAt});

  @JsonKey(name: r'displayName', required: false, includeIfNull: false)
  final String? displayName;

  @JsonKey(name: r'upiVpa', required: false, includeIfNull: false)
  final String? upiVpa;

  @JsonKey(name: r'leftAt', required: false, includeIfNull: false)
  final DateTime? leftAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberPatch &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa &&
          other.leftAt == leftAt;

  @override
  int get hashCode =>
      displayName.hashCode +
      (upiVpa == null ? 0 : upiVpa.hashCode) +
      (leftAt == null ? 0 : leftAt.hashCode);

  factory MemberPatch.fromJson(Map<String, dynamic> json) =>
      _$MemberPatchFromJson(json);

  Map<String, dynamic> toJson() => _$MemberPatchToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
