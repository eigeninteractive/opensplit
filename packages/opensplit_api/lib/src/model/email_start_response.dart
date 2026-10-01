//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/email_flow.dart';
import 'package:json_annotation/json_annotation.dart';

part 'email_start_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class EmailStartResponse {
  /// Returns a new [EmailStartResponse] instance.
  EmailStartResponse({required this.flow});

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
      other is EmailStartResponse && other.flow == flow;

  @override
  int get hashCode => flow.hashCode;

  factory EmailStartResponse.fromJson(Map<String, dynamic> json) =>
      _$EmailStartResponseFromJson(json);

  Map<String, dynamic> toJson() => _$EmailStartResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
