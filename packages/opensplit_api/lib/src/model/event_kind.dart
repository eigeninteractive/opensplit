//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum EventKind {
  @JsonValue(r'entry')
  entry(r'entry'),
  @JsonValue(r'member_added')
  memberAdded(r'member_added'),
  @JsonValue(r'member_joined')
  memberJoined(r'member_joined'),
  @JsonValue(r'member_left')
  memberLeft(r'member_left'),
  @JsonValue(r'member_renamed')
  memberRenamed(r'member_renamed'),
  @JsonValue(r'group_renamed')
  groupRenamed(r'group_renamed'),
  @JsonValue(r'group_archived')
  groupArchived(r'group_archived'),
  @JsonValue(r'group_restored')
  groupRestored(r'group_restored'),
  @JsonValue(r'link_created')
  linkCreated(r'link_created'),
  @JsonValue(r'link_revoked')
  linkRevoked(r'link_revoked'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const EventKind(this.value);

  final String value;

  @override
  String toString() => value;
}
