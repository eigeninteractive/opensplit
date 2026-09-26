//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'google_redirect_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GoogleRedirectRequest {
  /// Returns a new [GoogleRedirectRequest] instance.
  GoogleRedirectRequest({required this.callbackUrl, required this.allowSignIn});

  @JsonKey(name: r'callbackUrl', required: true, includeIfNull: false)
  final String callbackUrl;

  @JsonKey(name: r'allowSignIn', required: true, includeIfNull: false)
  final bool allowSignIn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleRedirectRequest &&
          other.callbackUrl == callbackUrl &&
          other.allowSignIn == allowSignIn;

  @override
  int get hashCode => callbackUrl.hashCode + allowSignIn.hashCode;

  factory GoogleRedirectRequest.fromJson(Map<String, dynamic> json) =>
      _$GoogleRedirectRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GoogleRedirectRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
