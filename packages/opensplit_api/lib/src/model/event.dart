//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/entry_snapshot.dart';
import 'package:opensplit_api/src/model/event_kind.dart';
import 'package:opensplit_api/src/model/link_event_payload.dart';
import 'package:opensplit_api/src/model/group_event_payload.dart';
import 'package:opensplit_api/src/model/member_event_payload.dart';
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

    required this.entry,

    required this.member,

    required this.group,

    required this.link,

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

  @JsonKey(name: r'entry', required: true, includeIfNull: true)
  final EntrySnapshot? entry;

  @JsonKey(name: r'member', required: true, includeIfNull: true)
  final MemberEventPayload? member;

  @JsonKey(name: r'group', required: true, includeIfNull: true)
  final GroupEventPayload? group;

  @JsonKey(name: r'link', required: true, includeIfNull: true)
  final LinkEventPayload? link;

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
          other.entry == entry &&
          other.member == member &&
          other.group == group &&
          other.link == link &&
          other.seq == seq &&
          other.ordinal == ordinal;

  @override
  int get hashCode =>
      id.hashCode +
      (actorId == null ? 0 : actorId.hashCode) +
      createdAt.hashCode +
      kind.hashCode +
      (subjectId == null ? 0 : subjectId.hashCode) +
      (entry == null ? 0 : entry.hashCode) +
      (member == null ? 0 : member.hashCode) +
      (group == null ? 0 : group.hashCode) +
      (link == null ? 0 : link.hashCode) +
      seq.hashCode +
      ordinal.hashCode;

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);

  Map<String, dynamic> toJson() => _$EventToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
