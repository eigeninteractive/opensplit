import 'package:test/test.dart';

import '../../tool/verify_config.dart';

void main() {
  test('self-hosted HTTPS backends are valid release targets', () {
    expect(validateBackendUrl('https://ledger.example.org'), isNull);
    expect(validateBackendUrl('https://ledger.example.org:8443'), isNull);
    expect(validateBackendUrl('https://ledger.example.org/'), isNull);
    expect(validateBackendUrl('http://ledger.example.org'), isNotNull);
    expect(
      validateBackendUrl('https://user:password@ledger.example.org'),
      isNotNull,
    );
  });

  test('an origin with a path in it is refused', () {
    // Configuration names the host. The generated contract owns the API path.
    expect(validateBackendUrl('https://ledger.example.org/app'), isNotNull);
    expect(validateBackendUrl('https://ledger.example.org/api'), isNotNull);
  });

  /// There used to be a second test here, and its absence is the point.
}
