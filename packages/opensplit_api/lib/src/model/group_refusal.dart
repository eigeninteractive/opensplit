//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/error_code.dart';
import 'package:json_annotation/json_annotation.dart';

part 'group_refusal.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GroupRefusal {
  /// Returns a new [GroupRefusal] instance.
  GroupRefusal({
    required this.groupId,

    required this.code,

    required this.message,
  });

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(
    name: r'code',
    required: true,
    includeIfNull: false,
    unknownEnumValue: ErrorCode.unknownDefaultOpenApi,
  )
  final ErrorCode code;

  @JsonKey(name: r'message', required: true, includeIfNull: false)
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupRefusal &&
          other.groupId == groupId &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => groupId.hashCode + code.hashCode + message.hashCode;

  factory GroupRefusal.fromJson(Map<String, dynamic> json) =>
      _$GroupRefusalFromJson(json);

  Map<String, dynamic> toJson() => _$GroupRefusalToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
