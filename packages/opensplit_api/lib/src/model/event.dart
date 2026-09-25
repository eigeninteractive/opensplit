//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/event_kind.dart';
import 'package:json_annotation/json_annotation.dart';

part 'event.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Event {
  /// Returns a new [Event] instance.
  Event({
    required this.id,

    required this.actorId,

    required this.createdAt,

    required this.kind,

    required this.subjectId,

    required this.payload,

    required this.seq,

    required this.ordinal,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'actorId', required: true, includeIfNull: true)
  final String? actorId;

  @JsonKey(name: r'createdAt', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(
    name: r'kind',
    required: true,
    includeIfNull: false,
    unknownEnumValue: EventKind.unknownDefaultOpenApi,
  )
  final EventKind kind;

  @JsonKey(name: r'subjectId', required: true, includeIfNull: true)
  final String? subjectId;

  /// The after-image, in whatever shape `kind` calls for: EntrySnapshot, MemberEventPayload, GroupEventPayload or LinkEventPayload.
  @JsonKey(name: r'payload', required: true, includeIfNull: false)
  final Map<String, Object?> payload;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  // minimum: 0
  @JsonKey(name: r'ordinal', required: true, includeIfNull: false)
  final int ordinal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          other.id == id &&
          other.actorId == actorId &&
          other.createdAt == createdAt &&
          other.kind == kind &&
          other.subjectId == subjectId &&
          other.payload == payload &&
          other.seq == seq &&
          other.ordinal == ordinal;

  @override
  int get hashCode =>
      id.hashCode +
      (actorId == null ? 0 : actorId.hashCode) +
      createdAt.hashCode +
      kind.hashCode +
      (subjectId == null ? 0 : subjectId.hashCode) +
      payload.hashCode +
      seq.hashCode +
      ordinal.hashCode;

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);

  Map<String, dynamic> toJson() => _$EventToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
