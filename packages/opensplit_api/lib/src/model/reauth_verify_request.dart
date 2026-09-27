//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'reauth_verify_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReauthVerifyRequest {
  /// Returns a new [ReauthVerifyRequest] instance.
  ReauthVerifyRequest({required this.code});

  @JsonKey(name: r'code', required: true, includeIfNull: false)
  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReauthVerifyRequest && other.code == code;

  @override
  int get hashCode => code.hashCode;

  factory ReauthVerifyRequest.fromJson(Map<String, dynamic> json) =>
      _$ReauthVerifyRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ReauthVerifyRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
