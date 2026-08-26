import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show Widget;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';
// web_only.dart exists only in the web implementation of the plugin, so it
// cannot be imported unconditionally without breaking the Android build.
import 'google_button.dart'
    if (dart.library.js_interop) 'google_button_web.dart';

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
  /// Two platforms, two different answers to "how does a sign-in start", and
  /// this is where that stops being the caller's problem.
  ///
  /// Android has an interactive call: [obtainIdToken] awaits a token. The web
  /// does not — `supportsAuthenticate()` is false there and
  /// [GoogleSignIn.authenticate] throws `UnimplementedError`, because Google
  /// Identity Services will only begin a sign-in from a button it renders
  /// itself. So the web offers [button] and listens on [signIns] instead, and
  /// is just as configured as Android is.
  ///
  /// Platforms with no implementation registered at all — a unit test, a
  /// desktop build — report neither, and correctly offer nothing.
  static bool get isConfigured {
    if (googleWebClientId.isEmpty) return false;
    if (kIsWeb) return true;
    try {
      return GoogleSignIn.instance.supportsAuthenticate();
    } on UnimplementedError {
      return false;
    }
  }

  /// Whether starting the flow means awaiting a call rather than waiting for a
  /// button the user taps.
  static bool get startsOnDemand => !kIsWeb;

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
  ///
  /// Android only — see [startsOnDemand]. On the web this throws, because there
  /// is nothing to call.
  Future<GoogleCredential?> obtainIdToken() async {
    if (!isConfigured || !startsOnDemand) {
      throw StateError(
        'This build cannot start a Google sign-in on demand: it has no client '
        'id, or the platform only signs in from a button Google renders. Use '
        '[button] and [signIns], or an email code.',
      );
    }
    await _ensureInitialised();

    final account = await GoogleSignIn.instance.authenticate();
    return _credentialFor(account);
  }

  /// Google's own button, for the platform that will not start without one.
  ///
  /// Null off the web. Initialisation has to have happened before this renders,
  /// which is what [prepare] is for.
  Widget? button() => googleSignInButton();

  /// Readies the plugin so [button] can render and [signIns] can emit.
  Future<void> prepare() => _ensureInitialised();

  /// Sign-ins that began somewhere other than a call — which on the web is all
  /// of them.
  ///
  /// The credential arrives on a stream because the button is Google's: it does
  /// not return to a caller, it announces that somebody signed in. Sign-outs
  /// are filtered away rather than surfaced; this app's own session is what
  /// decides who is signed in, and Google's opinion of it is not something any
  /// screen should react to.
  static Stream<GoogleCredential> get signIns => GoogleSignIn
      .instance
      .authenticationEvents
      .where((event) => event is GoogleSignInAuthenticationEventSignIn)
      .cast<GoogleSignInAuthenticationEventSignIn>()
      .asyncMap((event) => _credentialFor(event.user))
      .where((credential) => credential != null)
      .cast<GoogleCredential>();

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

    return (idToken: idToken, accessToken: authorization?.accessToken);
  }
}

/// What Supabase needs to turn a Google sign-in into a session.
typedef GoogleCredential = ({String idToken, String? accessToken});
