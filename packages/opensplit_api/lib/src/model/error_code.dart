//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

enum ErrorCode {
  @JsonValue(r'not_member')
  notMember(r'not_member'),
  @JsonValue(r'no_group')
  noGroup(r'no_group'),
  @JsonValue(r'group_purged')
  groupPurged(r'group_purged'),
  @JsonValue(r'group_exists')
  groupExists(r'group_exists'),
  @JsonValue(r'no_such_entry')
  noSuchEntry(r'no_such_entry'),
  @JsonValue(r'no_such_member')
  noSuchMember(r'no_such_member'),
  @JsonValue(r'unbalanced')
  unbalanced(r'unbalanced'),
  @JsonValue(r'stale_base')
  staleBase(r'stale_base'),
  @JsonValue(r'forbidden')
  forbidden(r'forbidden'),
  @JsonValue(r'not_settled')
  notSettled(r'not_settled'),
  @JsonValue(r'invite_invalid')
  inviteInvalid(r'invite_invalid'),
  @JsonValue(r'invite_spent')
  inviteSpent(r'invite_spent'),
  @JsonValue(r'invite_expired')
  inviteExpired(r'invite_expired'),
  @JsonValue(r'already_member')
  alreadyMember(r'already_member'),
  @JsonValue(r'slot_taken')
  slotTaken(r'slot_taken'),
  @JsonValue(r'malformed')
  malformed(r'malformed'),
  @JsonValue(r'no_session')
  noSession(r'no_session'),
  @JsonValue(r'not_found')
  notFound(r'not_found'),
  @JsonValue(r'internal')
  internal(r'internal'),
  @JsonValue(r'identity_already_in_use')
  identityAlreadyInUse(r'identity_already_in_use'),
  @JsonValue(r'auth_failed')
  authFailed(r'auth_failed'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const ErrorCode(this.value);

  final String value;

  @override
  String toString() => value;
}
