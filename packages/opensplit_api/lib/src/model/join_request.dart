//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'join_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class JoinRequest {
  /// Returns a new [JoinRequest] instance.
  JoinRequest({required this.memberId, required this.displayName});

  @JsonKey(name: r'memberId', required: true, includeIfNull: true)
  final String? memberId;

  @JsonKey(name: r'displayName', required: true, includeIfNull: true)
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinRequest &&
          other.memberId == memberId &&
          other.displayName == displayName;

  @override
  int get hashCode =>
      (memberId == null ? 0 : memberId.hashCode) +
      (displayName == null ? 0 : displayName.hashCode);

  factory JoinRequest.fromJson(Map<String, dynamic> json) =>
      _$JoinRequestFromJson(json);

  Map<String, dynamic> toJson() => _$JoinRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
