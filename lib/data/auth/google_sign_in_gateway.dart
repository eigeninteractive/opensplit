import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';

/// A platform that can produce a Google ID token without leaving the app.
abstract interface class GoogleTokenSource {
  /// The credential, or null if the user backed out of the picker.
  Future<GoogleCredential?> obtainIdToken();
}

/// Obtains a Google ID token natively.
class GoogleSignInGateway implements GoogleTokenSource {
  /// Whether this build offers Google at all, on either platform.
  static bool get isOffered =>
      kIsWeb ? googleWebClientId.isNotEmpty : isConfigured;

  /// Whether this build can complete a Google sign-in without leaving the app.
  static bool get isConfigured {
    if (kIsWeb || googleWebClientId.isEmpty) return false;
    try {
      return GoogleSignIn.instance.supportsAuthenticate();
    } on UnimplementedError {
      return false;
    }
  }

  /// Held statically, and as the future rather than a flag.
  static Future<void>? _ready;

  /// The nonce every Google token from this session is bound to.
  static final String _nonce = base64Url
      .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static final Random _random = Random.secure();

  Future<void> _ensureInitialised() =>
      _ready ??= GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? googleWebClientId : null,
        // The same web client id on Android, deliberately: the Worker verifies
        // the ID token against this audience whichever platform minted it.
        serverClientId: kIsWeb ? null : googleWebClientId,
        nonce: sha256.convert(utf8.encode(_nonce)).toString(),
      );

  /// Returns the ID token, or null if the user backed out.
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

    // Best effort.
    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    return (
      idToken: idToken,
      accessToken: authorization?.accessToken,
      nonce: _nonce,
    );
  }
}

/// What the server needs to turn a Google sign-in into a session.
typedef GoogleCredential = ({
  String idToken,
  String? accessToken,
  String nonce,
});
