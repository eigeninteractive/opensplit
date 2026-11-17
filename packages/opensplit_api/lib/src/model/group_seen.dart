//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_seen.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupSeen {
  /// Returns a new [GroupSeen] instance.
  GroupSeen({required this.groupId, required this.seenAt});

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(name: r'seenAt', required: true, includeIfNull: false)
  final DateTime seenAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupSeen && other.groupId == groupId && other.seenAt == seenAt;

  @override
  int get hashCode => groupId.hashCode + seenAt.hashCode;

  factory GroupSeen.fromJson(Map<String, dynamic> json) =>
      _$GroupSeenFromJson(json);

  Map<String, dynamic> toJson() => _$GroupSeenToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
