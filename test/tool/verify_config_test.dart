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
    // The client appends `/api/...` to this, so a trailing path would produce
    // `/app/api/bootstrap` and a 404 that reads as an outage rather than as a
    // mistyped config value — which is the kind of thing that costs an
    // afternoon precisely because the app still launches.
    expect(validateBackendUrl('https://ledger.example.org/app'), isNotNull);
    expect(validateBackendUrl('https://ledger.example.org/api'), isNotNull);
  });

  /// There used to be a second test here, and its absence is the point.
  ///
  /// It checked that a publishable key was one, and above all that it was not a
  /// service-role key somebody had pasted in by mistake — which would have put
  /// full database access inside a web bundle anybody can read.
  ///
  /// The backend is now one origin serving the site, the app bundle and the
  /// API, and a request carries a session or it carries nothing. There is no
  /// anonymous public identifier to configure, so there is nothing here that
  /// could be the wrong one.
}
