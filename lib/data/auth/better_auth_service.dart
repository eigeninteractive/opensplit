import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/repositories/auth_service.dart';
import '../sync/api_client.dart';
import 'browser_navigator.dart';
import 'google_sign_in_gateway.dart';
import 'pending_identity_redirect.dart';
import 'session_store.dart';

/// The session, through the server's `/api/identity` routes, which wrap Better
/// Auth and answer in contract types.
final class BetterAuthService implements AuthService {
  BetterAuthService({
    required this.client,
    required this.sessions,
    StoredSession? restored,
    this.googleTokens,
    this.pending = const PendingIdentityRedirects(),
    this.leaveFor = navigateBrowser,
  }) : _current = restored?.account {
    // The restored account is a cache; the server's answer arrives on the
    // stream. Unawaited so launching never waits on the network.
    unawaited(_revalidate());
  }

  final api.OpensplitApi client;
  final SessionStore sessions;

  /// In-process Google sign-in; null on the web, which redirects instead.
  final GoogleTokenSource? googleTokens;

  final PendingIdentityRedirects pending;
  final void Function(String url) leaveFor;

  Account? _current;
  final _changes = StreamController<Account?>.broadcast();

  api.IdentityApi get _identity => client.getIdentityApi();

  @override
  Account? get currentUser => _current;

  @override
  Stream<Account?> authStateChanges() => _changes.stream;

  @override
  Future<Account> signInAnonymously() async =>
      (await _settle(await fetch(_identity.signInAsGuest()))).account;

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

    try {
      final outcome = await fetch(
        _identity.linkGoogle(
          googleIdentityRequest: api.GoogleIdentityRequest(
            idToken: credential.idToken,
            nonce: credential.nonce,
            allowSignIn: allowSignIn,
          ),
        ),
      );
      return AttemptCompleted(await _settle(outcome));
    } on ApiFailure catch (failure) {
      // Signing in would leave this device's ledger behind; the caller asks first.
      if (failure.code == api.ErrorCode.identityAlreadyInUse) {
        throw IdentityAlreadyInUse(failure.message);
      }
      rethrow;
    }
  }

  Future<GoogleAttempt> _startGoogleRedirect({
    required String returnTo,
    required bool allowSignIn,
  }) async {
    final before = _current?.id;
    await pending.write(
      PendingIdentityRedirect(
        intent: before == null || allowSignIn
            ? IdentityIntent.signIn
            : IdentityIntent.link,
        previousUserId: before,
        returnTo: returnTo,
        startedAt: DateTime.now(),
      ),
    );

    try {
      final redirect = await fetch(
        _identity.startGoogleRedirect(
          googleRedirectRequest: api.GoogleRedirectRequest(
            callbackUrl: googleRedirectUrl(Uri.base, returnTo),
            allowSignIn: allowSignIn,
          ),
        ),
      );
      leaveFor(redirect.url);
    } catch (_) {
      // The page never left, so a stale record would fire on the next launch.
      await pending.clear();
      rethrow;
    }
    return const AttemptRedirected();
  }

  @override
  Future<IdentityOutcome?> resumeIdentityRedirect() async {
    final departure = await pending.take();
    if (departure == null) return null;

    final refusal = _refusalInCallbackUrl();
    if (refusal != null) {
      if (departure.intent == IdentityIntent.link) throw refusal;
      return null;
    }

    // The browser came back with a cookie the page cannot read, so ask.
    final account = await _revalidate();
    if (account == null) return null;

    final previous = departure.previousUserId;
    return previous == null || previous == account.id
        ? SessionKept(account: account)
        : SessionReplaced(account: account, strandedUserId: previous);
  }

  @override
  Future<EmailFlow> sendEmailCode(String email) async {
    final response = await fetch(
      _identity.startEmailSignIn(
        emailStartRequest: api.EmailStartRequest(email: email),
      ),
    );
    // A flow this build cannot name is read as the one that replaces nothing
    // by itself; verifying reports what actually happened.
    return response.flow == EmailFlow.linkPending
        ? EmailFlow.linkPending
        : EmailFlow.signInPending;
  }

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async => _settle(
    await fetch(
      _identity.verifyEmailCode(
        emailVerifyRequest: api.EmailVerifyRequest(
          email: email,
          code: code,
          flow: flow,
        ),
      ),
    ),
  );

  @override
  Future<void> signOut() async {
    try {
      await send(_identity.signOut());
    } on ApiFailure {
      // The device signs out regardless; an orphaned session row expires.
    }
    await _adopt(null, token: null);
  }

  @override
  Future<void> deleteAccount() async {
    await fetch(client.getAccountApi().deleteAccount());
    // The session went with the account.
    await _adopt(null, token: null);
  }

  /// Asks the server who this device is. Never throws (the constructor does not
  /// await it): anything but an answer leaves the cached account alone, since
  /// the app renders from the local database either way. An answer overtaken by
  /// a sign-in is dropped, or it would sign that session out.
  Future<Account?> _revalidate() async {
    final asked = _current?.id;
    final api.Session session;
    try {
      session = await fetch(_identity.getSession());
    } on Object {
      return _current;
    }
    // A sign-in finished while this was in flight; its answer is newer.
    if (_current?.id != asked) return _current;
    return _adopt(
      session.account,
      token: session.token ?? sessions.read()?.token,
    );
  }

  /// The one place the account changes: stored, set on the client, announced.
  Future<Account?> _adopt(Account? account, {required String? token}) async {
    // On the web the session is an HttpOnly cookie; a readable token would
    // undo that, so none is kept.
    final bearer = kIsWeb || account == null ? null : token;
    await sessions.write(
      account == null ? null : StoredSession(account: account, token: bearer),
    );
    if (bearer == null) {
      client.removeBearerAuth(bearerScheme);
    } else {
      client.setBearerAuth(bearerScheme, bearer);
    }

    _current = account;
    if (!_changes.isClosed) _changes.add(account);
    return account;
  }

  Future<IdentityOutcome> _settle(api.IdentityOutcome body) async {
    await _adopt(body.account, token: body.token);
    return body.outcome == api.IdentityOutcomeKind.replaced
        ? SessionReplaced(
            account: body.account,
            strandedUserId: body.strandedUserId ?? body.account.id,
          )
        : SessionKept(account: body.account);
  }

  IdentityAlreadyInUse? _refusalInCallbackUrl() {
    final parameters = Uri.base.queryParameters;
    final code = parameters['error'] ?? parameters['error_code'];
    if (code == null) return null;

    final description = parameters['error_description'] ?? '';
    if (!code.contains('already') && !description.contains('already')) {
      return null;
    }
    return const IdentityAlreadyInUse(
      'That Google account already has an OpenSplit account of its own.',
    );
  }

  void dispose() => _changes.close();
}

/// Where Google sends the browser back to: the welcome screen, which finishes
/// the flow and continues to [returnTo].
String googleRedirectUrl(Uri base, String returnTo) {
  final underAppPrefix = base.path == '/app' || base.path.startsWith('/app/');
  return Uri.parse(base.origin)
      .replace(
        path: '${underAppPrefix ? '/app' : ''}/welcome',
        queryParameters: {'from': returnTo},
      )
      .toString();
}
