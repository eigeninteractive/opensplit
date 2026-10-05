//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_cursor.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupCursor {
  /// Returns a new [GroupCursor] instance.
  GroupCursor({required this.groupId, required this.since});

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  // minimum: 0
  @JsonKey(name: r'since', required: true, includeIfNull: false)
  final int since;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupCursor && other.groupId == groupId && other.since == since;

  @override
  int get hashCode => groupId.hashCode + since.hashCode;

  factory GroupCursor.fromJson(Map<String, dynamic> json) =>
      _$GroupCursorFromJson(json);

  Map<String, dynamic> toJson() => _$GroupCursorToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
