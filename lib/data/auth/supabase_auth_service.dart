import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/repositories/auth_service.dart';
import 'google_sign_in_gateway.dart';
import 'pending_identity_redirect.dart';

/// Supabase-backed identity.
///
/// The whole of the care in this file is about one distinction: attaching an
/// identity to the session you already have, versus authenticating as whoever
/// owns that identity. `signInWithIdToken` and `signInWithOtp` are the second
/// thing. Called on an anonymous session they do not upgrade it — they mint or
/// resume a *different* user and leave the anonymous one holding every group
/// the person has created so far, at which point the new account is a stranger
/// to its own data and every push is refused by row-level security.
///
/// So each entry point below tries the linking call first and only falls back
/// when the identity provably belongs to somebody already, and it reports which
/// of the two happened so the caller can say so.
final class SupabaseAuthService implements AuthService {
  SupabaseAuthService(
    this._client, {
    this.googleTokens,
    this.pending = const PendingIdentityRedirects(),
  });

  final sb.SupabaseClient _client;

  /// How this platform gets a Google ID token without leaving the app.
  ///
  /// Null on the web, and that null is the whole platform switch. Google
  /// Identity Services answers into an iframe or a popup, and neither survives
  /// the cross-origin isolation the local database needs, so the browser is
  /// sent to Google instead and comes back with a session already made.
  final GoogleTokenSource? googleTokens;

  final PendingIdentityRedirects pending;

  /// Codes meaning "that identity is already somebody's".
  ///
  /// The only condition under which falling back to a sign-in is right. Any
  /// other failure is rethrown: a fallback that fires on, say, a network blip
  /// would sign the user out of their own data for no reason.
  static const _alreadyClaimed = {
    'identity_already_exists',
    'email_exists',
    'user_already_exists',
  };

  Account? _toUser(sb.User? user) => user == null
      ? null
      : Account(
          id: user.id,
          isAnonymous: user.isAnonymous,
          email: user.email,
          displayName: user.userMetadata?['display_name'] as String?,
        );

  /// Decides which outcome just happened.
  ///
  /// The comparison lives here rather than in the type because it is the data
  /// layer that knows both halves: no caller should be handed two ids and told
  /// to work it out.
  IdentityOutcome _outcomeFor(Account account, String? previousUserId) =>
      previousUserId == null || previousUserId == account.id
      ? SessionKept(account: account)
      : SessionReplaced(account: account, strandedUserId: previousUserId);

  Account _require(sb.User? user, String what) {
    final account = _toUser(user);
    if (account == null) throw StateError('$what returned no user');
    return account;
  }

  /// Turns the one operator mistake that looks like a user problem into a
  /// sentence naming the switch that is off.
  ///
  /// Manual linking is disabled by default on a Supabase project. With it off,
  /// every link attempt fails and the only thing standing between that and
  /// silently destroying somebody's data is that this does not fall through.
  Never _rethrowLinkFailure(sb.AuthException error) {
    if (error.code == 'manual_linking_disabled') {
      throw const sb.AuthException(
        'This deployment has manual account linking switched off, so an '
        'account cannot be attached to an existing session. Enable it under '
        'Authentication → Providers → Allow manual linking.',
        code: 'manual_linking_disabled',
      );
    }
    throw error;
  }

  @override
  Account? get currentUser => _toUser(_client.auth.currentUser);

  @override
  Stream<Account?> authStateChanges() => _client.auth.onAuthStateChange.map(
    (event) => _toUser(event.session?.user),
  );

  @override
  Future<Account> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    return _require(response.user, 'Anonymous sign-in');
  }

  @override
  Future<GoogleAttempt> continueWithGoogle({
    required String returnTo,
    bool allowSignIn = false,
  }) async {
    final tokens = googleTokens;
    if (tokens == null) {
      return _startGoogleRedirect(returnTo: returnTo, allowSignIn: allowSignIn);
    }
    final credential = await tokens.obtainIdToken();
    if (credential == null) return const AttemptCancelled();
    return AttemptCompleted(
      await _exchangeGoogleToken(credential, allowSignIn: allowSignIn),
    );
  }

  /// The in-process half: a token is already in hand, so link-then-recover can
  /// happen inside one call and the user never leaves the app.
  Future<IdentityOutcome> _exchangeGoogleToken(
    GoogleCredential credential, {
    required bool allowSignIn,
  }) async {
    final idToken = credential.idToken;
    final accessToken = credential.accessToken;
    final nonce = credential.nonce;
    final before = _client.auth.currentUser?.id;

    // Nobody is signed in, so there is nothing to link this to and nothing at
    // stake. Straight to a sign-in, which for a new address is a sign-up.
    if (before == null) {
      final response = await _client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );
      return _outcomeFor(_require(response.user, 'Google sign-in'), null);
    }

    // linkIdentityWithIdToken is the linking half of the same endpoint — it
    // sets `link_identity` — and it exists precisely because signInWithIdToken
    // cannot do this.
    try {
      final response = await _client.auth.linkIdentityWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );
      return _outcomeFor(_require(response.user, 'Linking Google'), before);
    } on sb.AuthException catch (error) {
      if (!_alreadyClaimed.contains(error.code)) _rethrowLinkFailure(error);
      if (!allowSignIn) {
        throw const IdentityAlreadyInUse(
          'That Google account already has an OpenSplit account of its own.',
        );
      }
    }

    // That Google account already belongs to somebody, so this is a sign-in.
    // Usually to a different account — but not always: if it is the same
    // address as the email account already holding this session, Supabase
    // attaches the identity to it and the user id does not change at all.
    // _outcomeFor works that out from the ids rather than assuming.
    final response = await _client.auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
    );
    return _outcomeFor(_require(response.user, 'Google sign-in'), before);
  }

  /// The redirect half: the page leaves, so every decision has to be made now.
  ///
  /// [allowSignIn] is read differently here than on the in-process path, and
  /// the difference is forced rather than chosen. There, a link can be tried
  /// and the refusal recovered from inside one call. Here the refusal only
  /// comes back after a round trip, so a second attempt that tried linking
  /// again would loop forever. The flag therefore means "the refusal has
  /// already been shown and accepted", which is the only condition under which
  /// any caller sets it.
  Future<GoogleAttempt> _startGoogleRedirect({
    required String returnTo,
    required bool allowSignIn,
  }) async {
    final before = _client.auth.currentUser?.id;
    // Nobody signed in means nothing to attach to, so it can only be a
    // sign-in — the same reasoning the in-process path uses.
    final intent = before == null || allowSignIn
        ? IdentityIntent.signIn
        : IdentityIntent.link;

    await pending.write(
      PendingIdentityRedirect(
        intent: intent,
        previousUserId: before,
        returnTo: returnTo,
        startedAt: DateTime.now(),
      ),
    );

    final redirectTo = _redirectUrlFor(returnTo);
    try {
      if (intent == IdentityIntent.link) {
        await _client.auth.linkIdentity(
          sb.OAuthProvider.google,
          redirectTo: redirectTo,
        );
      } else {
        await _client.auth.signInWithOAuth(
          sb.OAuthProvider.google,
          redirectTo: redirectTo,
        );
      }
    } catch (_) {
      // The page never left, so nothing is pending and a stale record would
      // fire against the next launch.
      await pending.clear();
      rethrow;
    }
    return const AttemptRedirected();
  }

  @override
  Future<IdentityOutcome?> resumeIdentityRedirect() async {
    final departure = await pending.take();
    if (departure == null) return null;

    // Safe to read straight away: `Supabase.initialize` awaits its own handling
    // of the callback URL before returning, and this is called after it, so the
    // exchange has already succeeded or already failed.
    final refusal = _refusalInCallbackUrl();
    if (refusal != null) {
      if (departure.intent == IdentityIntent.link) throw refusal;
      // A sign-in that Google or GoTrue refused outright. Nothing changed.
      return null;
    }

    final user = _client.auth.currentUser;
    // Came back with no session at all: dismissed at Google, or the code
    // exchange failed. Nothing happened and there is nothing to report.
    if (user == null) return null;

    return _outcomeFor(
      _require(user, 'Google sign-in'),
      departure.previousUserId,
    );
  }

  /// The already-claimed refusal, if the callback carried one.
  ///
  /// Readable at all only because `supabase_flutter` clears the callback
  /// parameters on success and leaves them alone on failure, so a refused
  /// return still has them in the address bar when this runs.
  IdentityAlreadyInUse? _refusalInCallbackUrl() {
    final parameters = {
      ...Uri.base.queryParameters,
      // GoTrue puts them in the fragment for the implicit flow and the query
      // for PKCE; reading both costs nothing and avoids depending on which.
      ...Uri.splitQueryString(Uri.base.fragment),
    };
    final code = parameters['error_code'] ?? parameters['error'];
    if (code == null) return null;
    if (!_alreadyClaimed.contains(code) &&
        !(parameters['error_description'] ?? '').contains('already')) {
      return null;
    }
    return const IdentityAlreadyInUse(
      'That Google account already has an OpenSplit account of its own.',
    );
  }

  /// Where Google should send the browser back to.
  ///
  /// Lands on `/welcome` carrying the real destination, rather than on the
  /// destination itself, because the router already knows how to finish that
  /// journey: a signed-in arrival at `/welcome` is sent to `from`, and
  /// `safeReturnLocation` refuses anything that is not an internal route. So
  /// an invite opened by somebody with no session ends on the invite, and a
  /// tampered `from` cannot be turned into an open redirect.
  ///
  /// The `/app` prefix mirrors the rule in `redirectAppRoute`: production
  /// serves the client under it and a local `flutter run` serves it at the
  /// root, and this has to agree with whichever is running.
  String _redirectUrlFor(String returnTo) =>
      googleRedirectUrl(Uri.base, returnTo);

  @override
  Future<EmailFlow> sendEmailCode(String email) async {
    // Nobody is signed in: this is somebody arriving, so it is a sign-in, and
    // for an address with no account yet it is a sign-up. shouldCreateUser is
    // left at its default here, and only here — creating the account IS the
    // request.
    if (_client.auth.currentUser == null) {
      await _client.auth.signInWithOtp(email: email);
      return EmailFlow.signInPending;
    }

    // updateUser attaches the address to the session in hand, which is what
    // keeps the user id — and therefore every group on this device — intact.
    // It sends an email-change token, so verification has to use
    // OtpType.emailChange rather than OtpType.email.
    try {
      final response = await _client.auth.updateUser(
        sb.UserAttributes(email: email),
      );
      // A deployment with MAILER_AUTOCONFIRM on applies the change outright and
      // sends nothing. Reporting a pending code there would leave the caller
      // waiting on mail that was never generated.
      final applied =
          response.user?.email?.toLowerCase() == email.trim().toLowerCase();
      return applied ? EmailFlow.linked : EmailFlow.linkPending;
    } on sb.AuthException catch (error) {
      if (!_alreadyClaimed.contains(error.code)) _rethrowLinkFailure(error);
    }

    // shouldCreateUser: false is load-bearing. The default is true, and this
    // line is only reached because the address provably belongs to somebody
    // already — so if that turns out to be wrong, the default would silently
    // mint a brand new empty account, replace the session with it, and strand
    // every group recorded on this device under the anonymous user that wrote
    // them. Refusing is the recoverable outcome; creating is not.
    await _client.auth.signInWithOtp(email: email, shouldCreateUser: false);
    return EmailFlow.signInPending;
  }

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    assert(flow != EmailFlow.linked, 'nothing to verify: already attached');
    final linking = flow == EmailFlow.linkPending;

    final before = _client.auth.currentUser?.id;
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      // The two flows issue different token types and each rejects the other's,
      // with a message about an expired code that says nothing about why.
      type: linking ? sb.OtpType.emailChange : sb.OtpType.email,
    );
    return _outcomeFor(_require(response.user, 'Code verification'), before);
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 15));
    } catch (_) {
      // GoTrue clears local auth before revoking its remote session. Losing
      // connectivity after that must not report a local sign-out as failed.
      if (_client.auth.currentUser != null) rethrow;
    }
  }

  @override
  Future<void> deleteAccount() async {
    // An RPC rather than the admin API. Deleting a user through GoTrue needs
    // the service-role key, which cannot be in a client — so the capability
    // lives in the database as a SECURITY DEFINER function that takes no
    // arguments and reads auth.uid() itself. There is no parameter to point at
    // somebody else's account.
    await _client.rpc<void>('delete_account');
  }
}

/// Where Google should send the browser back to, given the page it left from.
///
/// Separate from the service and taking [base] rather than reading `Uri.base`
/// because this is the part that silently sends people to the wrong host, and
/// a global no test can set is a part no test can check.
///
/// The `/app` prefix mirrors the rule in `redirectAppRoute`: production serves
/// the client under it and a local `flutter run` serves it at the root, so the
/// answer has to follow whichever is running rather than be configured.
String googleRedirectUrl(Uri base, String returnTo) {
  final underAppPrefix = base.path == '/app' || base.path.startsWith('/app/');
  return Uri.parse(base.origin)
      .replace(
        path: '${underAppPrefix ? '/app' : ''}/welcome',
        queryParameters: {'from': returnTo},
      )
      .toString();
}
