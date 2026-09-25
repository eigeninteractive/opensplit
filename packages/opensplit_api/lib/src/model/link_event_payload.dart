//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'link_event_payload.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LinkEventPayload {
  /// Returns a new [LinkEventPayload] instance.
  LinkEventPayload({required this.expiresAt});

  @JsonKey(name: r'expiresAt', required: true, includeIfNull: false)
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkEventPayload && other.expiresAt == expiresAt;

  @override
  int get hashCode => expiresAt.hashCode;

  factory LinkEventPayload.fromJson(Map<String, dynamic> json) =>
      _$LinkEventPayloadFromJson(json);

  Map<String, dynamic> toJson() => _$LinkEventPayloadToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
