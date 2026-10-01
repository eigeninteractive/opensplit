//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// linkPending: verifying keeps the current account id. signInPending: the address already has an account, so verifying replaces the session.
enum EmailFlow {
  @JsonValue(r'linkPending')
  linkPending(r'linkPending'),
  @JsonValue(r'signInPending')
  signInPending(r'signInPending'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const EmailFlow(this.value);

  final String value;

  @override
  String toString() => value;
}
