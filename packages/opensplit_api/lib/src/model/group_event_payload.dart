//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'group_event_payload.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupEventPayload {
  /// Returns a new [GroupEventPayload] instance.
  GroupEventPayload({required this.name, required this.previousName});

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'previousName', required: true, includeIfNull: true)
  final String? previousName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupEventPayload &&
          other.name == name &&
          other.previousName == previousName;

  @override
  int get hashCode =>
      name.hashCode + (previousName == null ? 0 : previousName.hashCode);

  factory GroupEventPayload.fromJson(Map<String, dynamic> json) =>
      _$GroupEventPayloadFromJson(json);

  Map<String, dynamic> toJson() => _$GroupEventPayloadToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
