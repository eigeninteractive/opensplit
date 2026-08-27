import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/verify_config.dart';

void main() {
  test('self-hosted HTTPS backends are valid release targets', () {
    expect(validateBackendUrl('https://ledger.example.org'), isNull);
    expect(validateBackendUrl('https://ledger.example.org:8443'), isNull);
    expect(validateBackendUrl('http://ledger.example.org'), isNotNull);
    expect(
      validateBackendUrl('https://user:password@ledger.example.org'),
      isNotNull,
    );
  });

  test('privileged server keys cannot enter a client build', () {
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(validatePublishableKey('sb_publishable_example'), isNull);
    expect(validatePublishableKey(jwt('anon')), isNull);
    expect(validatePublishableKey(jwt('service_role')), isNotNull);
    expect(validatePublishableKey('sb_secret_example'), isNotNull);
  });
}
