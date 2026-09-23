//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'google_identity_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GoogleIdentityRequest {
  /// Returns a new [GoogleIdentityRequest] instance.
  GoogleIdentityRequest({
    required this.idToken,

    this.nonce,

    this.allowSignIn = false,
  });

  @JsonKey(name: r'idToken', required: true, includeIfNull: false)
  final String idToken;

  @JsonKey(name: r'nonce', required: false, includeIfNull: false)
  final String? nonce;

  @JsonKey(
    defaultValue: false,
    name: r'allowSignIn',
    required: false,
    includeIfNull: false,
  )
  final bool? allowSignIn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleIdentityRequest &&
          other.idToken == idToken &&
          other.nonce == nonce &&
          other.allowSignIn == allowSignIn;

  @override
  int get hashCode => idToken.hashCode + nonce.hashCode + allowSignIn.hashCode;

  factory GoogleIdentityRequest.fromJson(Map<String, dynamic> json) =>
      _$GoogleIdentityRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GoogleIdentityRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
