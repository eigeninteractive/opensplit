//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'email_start_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class EmailStartRequest {
  /// Returns a new [EmailStartRequest] instance.
  EmailStartRequest({required this.email});

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailStartRequest && other.email == email;

  @override
  int get hashCode => email.hashCode;

  factory EmailStartRequest.fromJson(Map<String, dynamic> json) =>
      _$EmailStartRequestFromJson(json);

  Map<String, dynamic> toJson() => _$EmailStartRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
