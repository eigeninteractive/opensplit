import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';

/// Obtains a Google ID token natively.
///
/// The native flow rather than the OAuth web redirect: one tap, no browser
/// bounce, and it returns an ID token that can be exchanged directly for a
/// session. The redirect flow leaves the app, loses context on the way back,
/// and is markedly worse on Android.
///
/// Inert until client IDs are configured, which have to come from a Google
/// Cloud project. [isConfigured] gates the button so an unconfigured build
/// simply does not offer it, rather than offering it and failing.
class GoogleSignInGateway {
  static bool get isConfigured =>
      googleServerClientId.isNotEmpty &&
      (!kIsWeb || googleWebClientId.isNotEmpty);

  bool _initialised = false;

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? googleWebClientId : null,
      // Supabase verifies the ID token against this audience, so it must match
      // the web client id of the same Google Cloud project even on Android.
      serverClientId: googleServerClientId,
    );
    _initialised = true;
  }

  /// Returns the ID token, or null if the user backed out.
  Future<({String idToken, String? accessToken})?> obtainIdToken() async {
    if (!isConfigured) {
      throw StateError('Google sign-in has no client id configured');
    }
    await _ensureInitialised();

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) return null;

    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    return (idToken: idToken, accessToken: authorization?.accessToken);
  }
}
