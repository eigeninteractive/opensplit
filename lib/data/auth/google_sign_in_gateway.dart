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
  /// Whether this build can actually complete the flow, not merely whether it
  /// was given a client id.
  ///
  /// The web implementation of `google_sign_in` reports
  /// `supportsAuthenticate() == false` and throws `UnimplementedError` from
  /// [GoogleSignIn.authenticate]: Google Identity Services will only start a
  /// sign-in from a button it renders itself, so there is no call to make. A
  /// build that has the client id — which every web build does, it is the same
  /// define — would otherwise show the button and fail on tap. Email codes work
  /// everywhere and are the path web offers instead; wiring `renderButton`, or
  /// the OAuth redirect via `linkIdentity`, is the follow-up that brings Google
  /// to the web.
  ///
  /// Platforms with no implementation registered at all — a unit test, a
  /// desktop build — throw from the same call, and are equally unable to offer
  /// it.
  static bool get isConfigured {
    if (googleWebClientId.isEmpty) return false;
    try {
      return GoogleSignIn.instance.supportsAuthenticate();
    } on UnimplementedError {
      return false;
    }
  }

  /// Held statically, and as the future rather than a flag.
  ///
  /// `GoogleSignIn.instance` is a singleton and `initialize` subscribes to its
  /// platform event stream, so calling it a second time attaches a second
  /// listener that nothing ever cancels. This class is constructed fresh on
  /// every tap, so a per-instance flag would have re-initialised every time.
  /// Storing the future also means two taps in quick succession await the same
  /// initialisation rather than racing it.
  static Future<void>? _ready;

  Future<void> _ensureInitialised() =>
      _ready ??= GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? googleWebClientId : null,
        // The same web client id on Android, deliberately: Supabase verifies
        // the ID token against this audience whichever platform minted it.
        serverClientId: googleWebClientId,
      );

  /// Returns the ID token, or null if the user backed out.
  Future<({String idToken, String? accessToken})?> obtainIdToken() async {
    if (!isConfigured) {
      throw StateError(
        'This build cannot start a Google sign-in: it has no client id, or '
        'the platform has no interactive flow to start. Use an email code.',
      );
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
