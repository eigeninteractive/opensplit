//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/event_kind.dart';
import 'package:json_annotation/json_annotation.dart';

part 'push_data.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PushData {
  /// Returns a new [PushData] instance.
  PushData({
    required this.groupId,

    required this.eventId,

    required this.kind,

    required this.subjectId,
  });

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(name: r'eventId', required: true, includeIfNull: false)
  final String eventId;

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: EventKind.unknownDefaultOpenApi,
  )
  final EventKind kind;

  @JsonKey(name: r'subjectId', required: true, includeIfNull: false)
  final String subjectId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushData &&
          other.groupId == groupId &&
          other.eventId == eventId &&
          other.kind == kind &&
          other.subjectId == subjectId;

  @override
  int get hashCode =>
      groupId.hashCode + eventId.hashCode + kind.hashCode + subjectId.hashCode;

  factory PushData.fromJson(Map<String, dynamic> json) =>
      _$PushDataFromJson(json);

  Map<String, dynamic> toJson() => _$PushDataToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
