//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

/// linkPending: verifying keeps the current account id, so every group on this device still belongs to it. signInPending: the address already had an account, so verifying REPLACES the session, and anything recorded as a guest stays with the guest account.
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
