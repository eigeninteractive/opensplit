import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';

/// A platform that can produce a Google ID token without leaving the app.
///
/// Exists so the auth service can be handed the capability rather than import
/// the plugin, and so its absence — the web — is expressible as a null rather
/// than as a `kIsWeb` branch buried in the middle of a sign-in.
abstract interface class GoogleTokenSource {
  /// The credential, or null if the user backed out of the picker.
  Future<GoogleCredential?> obtainIdToken();
}

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
class GoogleSignInGateway implements GoogleTokenSource {
  /// Whether this build can complete a Google sign-in without leaving the app.
  ///
  /// False on the web, and not because the web is unconfigured: there the
  /// browser is sent to Google and comes back with a session already made, so
  /// there is no token for this class to fetch and no reason for it to exist.
  /// [SupabaseAuthService] is handed null instead.
  /// Whether this build offers Google at all, on either platform.
  ///
  /// Distinct from [isConfigured], and a screen deciding whether to draw the
  /// button wants this one: the web offers Google and cannot mint a token for
  /// it, so asking "can this class get a token" would hide the button on the
  /// platform that needs it most.
  static bool get isOffered =>
      kIsWeb ? googleWebClientId.isNotEmpty : isConfigured;

  static bool get isConfigured {
    if (kIsWeb || googleWebClientId.isEmpty) return false;
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

  /// The nonce every Google token from this session is bound to.
  ///
  /// Generated once, because `initialize` fixes it for every token the plugin
  /// mints afterwards. Google is given its SHA-256 digest and Supabase the
  /// value itself: Supabase hashes what it receives and compares that against
  /// the token's claim, so the two sides must be given different halves.
  ///
  /// Supplying one is not optional. Asked for no nonce, `google_sign_in_web`
  /// puts the *string* `"null"` in the token, and Supabase then rejects a
  /// token whose nonce claim the request did not account for.
  static final String _nonce = base64Url
      .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static final Random _random = Random.secure();

  Future<void> _ensureInitialised() =>
      _ready ??= GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? googleWebClientId : null,
        // The same web client id on Android, deliberately: Supabase verifies
        // the ID token against this audience whichever platform minted it.
        // Null on the web, where the plugin rejects it outright: there the
        // audience is already `clientId`, so naming it twice is meaningless.
        serverClientId: kIsWeb ? null : googleWebClientId,
        nonce: sha256.convert(utf8.encode(_nonce)).toString(),
      );

  /// Returns the ID token, or null if the user backed out.
  ///
  /// Throws on a platform that cannot do this in-process — the web, which is
  /// handed no [GoogleTokenSource] at all and never reaches here.
  @override
  Future<GoogleCredential?> obtainIdToken() async {
    if (!isConfigured) {
      throw StateError(
        'This build cannot start a Google sign-in in-process: it has no client '
        'id, or the platform signs in by leaving the page. Use an email code.',
      );
    }
    await _ensureInitialised();

    final account = await GoogleSignIn.instance.authenticate();
    return _credentialFor(account);
  }

  static Future<GoogleCredential?> _credentialFor(
    GoogleSignInAccount account,
  ) async {
    final idToken = account.authentication.idToken;
    if (idToken == null) return null;

    // Best effort. The web hands back an ID token without an access token
    // unless the user is asked separately, and Supabase only needs the former —
    // it verifies the ID token's signature and audience itself.
    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    return (
      idToken: idToken,
      accessToken: authorization?.accessToken,
      nonce: _nonce,
    );
  }
}

/// What Supabase needs to turn a Google sign-in into a session.
typedef GoogleCredential = ({
  String idToken,
  String? accessToken,
  String nonce,
});
