//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/email_flow.dart';
import 'package:json_annotation/json_annotation.dart';

part 'email_verify_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class EmailVerifyRequest {
  /// Returns a new [EmailVerifyRequest] instance.
  EmailVerifyRequest({
    required this.email,

    required this.code,

    required this.flow,
  });

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @JsonKey(name: r'code', required: true, includeIfNull: false)
  final String code;

  @JsonKey(
    name: r'flow',
    required: true,
    includeIfNull: false,
    unknownEnumValue: EmailFlow.unknownDefaultOpenApi,
  )
  final EmailFlow flow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailVerifyRequest &&
          other.email == email &&
          other.code == code &&
          other.flow == flow;

  @override
  int get hashCode => email.hashCode + code.hashCode + flow.hashCode;

  factory EmailVerifyRequest.fromJson(Map<String, dynamic> json) =>
      _$EmailVerifyRequestFromJson(json);

  Map<String, dynamic> toJson() => _$EmailVerifyRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
