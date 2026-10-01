//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// kept: the account id did not change. replaced: a different account holds the session now, and `strandedUserId` names the one this device's ledger belongs to.
enum IdentityOutcomeKind {
  @JsonValue(r'kept')
  kept(r'kept'),
  @JsonValue(r'replaced')
  replaced(r'replaced'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const IdentityOutcomeKind(this.value);

  final String value;

  @override
  String toString() => value;
}
