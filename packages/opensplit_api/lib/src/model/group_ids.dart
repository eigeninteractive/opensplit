//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_ids.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupIds {
  /// Returns a new [GroupIds] instance.
  GroupIds({required this.groupIds});

  @JsonKey(name: r'groupIds', required: true, includeIfNull: false)
  final List<String> groupIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GroupIds && other.groupIds == groupIds;

  @override
  int get hashCode => groupIds.hashCode;

  factory GroupIds.fromJson(Map<String, dynamic> json) =>
      _$GroupIdsFromJson(json);

  Map<String, dynamic> toJson() => _$GroupIdsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
