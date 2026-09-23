//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:opensplit_api/src/model/event.dart';
import 'package:opensplit_api/src/model/group.dart';
import 'package:opensplit_api/src/model/entry.dart';
import 'package:opensplit_api/src/model/member.dart';
import 'package:json_annotation/json_annotation.dart';

part 'change_page.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChangePage {
  /// Returns a new [ChangePage] instance.
  ChangePage({
    required this.groupId,

    required this.seq,

    required this.hasMore,

    required this.group,

    required this.members,

    required this.entries,

    required this.events,

    required this.purgedAt,
  });

  @JsonKey(name: r'groupId', required: true, includeIfNull: false)
  final String groupId;

  // minimum: 0
  @JsonKey(name: r'seq', required: true, includeIfNull: false)
  final int seq;

  @JsonKey(name: r'hasMore', required: true, includeIfNull: false)
  final bool hasMore;

  @JsonKey(name: r'group', required: true, includeIfNull: true)
  final Group? group;

  @JsonKey(name: r'members', required: true, includeIfNull: false)
  final List<Member> members;

  @JsonKey(name: r'entries', required: true, includeIfNull: false)
  final List<Entry> entries;

  @JsonKey(name: r'events', required: true, includeIfNull: false)
  final List<Event> events;

  @JsonKey(name: r'purgedAt', required: true, includeIfNull: true)
  final DateTime? purgedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangePage &&
          other.groupId == groupId &&
          other.seq == seq &&
          other.hasMore == hasMore &&
          other.group == group &&
          other.members == members &&
          other.entries == entries &&
          other.events == events &&
          other.purgedAt == purgedAt;

  @override
  int get hashCode =>
      groupId.hashCode +
      seq.hashCode +
      hasMore.hashCode +
      (group == null ? 0 : group.hashCode) +
      members.hashCode +
      entries.hashCode +
      events.hashCode +
      (purgedAt == null ? 0 : purgedAt.hashCode);

  factory ChangePage.fromJson(Map<String, dynamic> json) =>
      _$ChangePageFromJson(json);

  Map<String, dynamic> toJson() => _$ChangePageToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
