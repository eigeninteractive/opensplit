//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/member.dart';
import 'package:json_annotation/json_annotation.dart';

part 'joined.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Joined {
  /// Returns a new [Joined] instance.
  Joined({required this.groupId, required this.member});

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(name: r'member', required: true, includeIfNull: false)
  final Member member;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Joined && other.groupId == groupId && other.member == member;

  @override
  int get hashCode => groupId.hashCode + member.hashCode;

  factory Joined.fromJson(Map<String, dynamic> json) => _$JoinedFromJson(json);

  Map<String, dynamic> toJson() => _$JoinedToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
