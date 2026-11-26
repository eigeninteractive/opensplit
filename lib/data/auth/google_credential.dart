/// A platform that can produce a Google ID token without leaving the app.
abstract interface class GoogleTokenSource {
  /// The credential, or null if the user backed out of the picker.
  Future<GoogleCredential?> obtainIdToken();
}

/// What the server needs to turn a Google sign-in into a session.
typedef GoogleCredential = ({
  String idToken,
  String? accessToken,
  String nonce,
});
