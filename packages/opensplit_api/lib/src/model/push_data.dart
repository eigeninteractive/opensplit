//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/push_kind.dart';
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

    this.currency,

    this.entryKind,
  });

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  @JsonKey(name: r'eventId', required: true, includeIfNull: false)
  final String eventId;

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: PushKind.unknownDefaultOpenApi,
  )
  final PushKind kind;

  @JsonKey(name: r'subjectId', required: true, includeIfNull: false)
  final String subjectId;

  @JsonKey(name: r'currency', required: false, includeIfNull: false)
  final String? currency;

  @JsonKey(
    name: r'entryKind',
    required: false,
    includeIfNull: false,
    unknownEnumValue: PushDataEntryKindEnum.unknownDefaultOpenApi,
  )
  final PushDataEntryKindEnum? entryKind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushData &&
          other.groupId == groupId &&
          other.eventId == eventId &&
          other.kind == kind &&
          other.subjectId == subjectId &&
          other.currency == currency &&
          other.entryKind == entryKind;

  @override
  int get hashCode =>
      groupId.hashCode +
      eventId.hashCode +
      kind.hashCode +
      subjectId.hashCode +
      currency.hashCode +
      entryKind.hashCode;

  factory PushData.fromJson(Map<String, dynamic> json) =>
      _$PushDataFromJson(json);

  Map<String, dynamic> toJson() => _$PushDataToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum PushDataEntryKindEnum {
  @JsonValue(r'expense')
  expense(r'expense'),
  @JsonValue(r'settlement')
  settlement(r'settlement'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const PushDataEntryKindEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
