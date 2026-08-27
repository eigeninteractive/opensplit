import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/repositories/auth_service.dart';

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
  SupabaseAuthService(this._client);

  final sb.SupabaseClient _client;

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
  Future<IdentityOutcome> continueWithGoogle({
    required String idToken,
    String? accessToken,
    bool allowSignIn = false,
  }) async {
    // The ID token flow rather than the OAuth web redirect: one tap, no browser
    // bounce, and markedly better on Android.
    final before = _client.auth.currentUser?.id;

    // Nobody is signed in, so there is nothing to link this to and nothing at
    // stake. Straight to a sign-in, which for a new address is a sign-up.
    if (before == null) {
      final response = await _client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return IdentityOutcome(
        account: _require(response.user, 'Google sign-in'),
        previousUserId: null,
      );
    }

    // linkIdentityWithIdToken is the linking half of the same endpoint — it
    // sets `link_identity` — and it exists precisely because signInWithIdToken
    // cannot do this.
    try {
      final response = await _client.auth.linkIdentityWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return IdentityOutcome(
        account: _require(response.user, 'Linking Google'),
        previousUserId: before,
      );
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
    // IdentityOutcome works that out from the ids rather than assuming.
    final response = await _client.auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    return IdentityOutcome(
      account: _require(response.user, 'Google sign-in'),
      previousUserId: before,
    );
  }

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
    return IdentityOutcome(
      account: _require(response.user, 'Code verification'),
      previousUserId: before,
    );
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
