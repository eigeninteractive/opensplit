//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'member_create.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MemberCreate {
  /// Returns a new [MemberCreate] instance.
  MemberCreate({required this.id, required this.displayName, this.upiVpa});

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @JsonKey(name: r'upiVpa', required: false, includeIfNull: false)
  final String? upiVpa;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberCreate &&
          other.id == id &&
          other.displayName == displayName &&
          other.upiVpa == upiVpa;

  @override
  int get hashCode =>
      id.hashCode +
      displayName.hashCode +
      (upiVpa == null ? 0 : upiVpa.hashCode);

  factory MemberCreate.fromJson(Map<String, dynamic> json) =>
      _$MemberCreateFromJson(json);

  Map<String, dynamic> toJson() => _$MemberCreateToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
