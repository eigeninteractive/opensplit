//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'member_event_payload.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MemberEventPayload {
  /// Returns a new [MemberEventPayload] instance.
  MemberEventPayload({required this.displayName, required this.previousName});

  @JsonKey(name: r'displayName', required: true, includeIfNull: false)
  final String displayName;

  @JsonKey(name: r'previousName', required: true, includeIfNull: true)
  final String? previousName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberEventPayload &&
          other.displayName == displayName &&
          other.previousName == previousName;

  @override
  int get hashCode =>
      displayName.hashCode + (previousName == null ? 0 : previousName.hashCode);

  factory MemberEventPayload.fromJson(Map<String, dynamic> json) =>
      _$MemberEventPayloadFromJson(json);

  Map<String, dynamic> toJson() => _$MemberEventPayloadToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
