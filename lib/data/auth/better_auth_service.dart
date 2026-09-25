import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/repositories/auth_service.dart';
import 'browser_navigator.dart';
import 'google_sign_in_gateway.dart';
import 'pending_identity_redirect.dart';
import 'session_store.dart';

/// Identity, against the Worker.
///
/// ## Why this is so much thinner than what it replaces
///
/// The distinction the whole of auth turns on — attaching an identity to the
/// session you already have, versus authenticating as whoever owns it — used to
/// live here, in four hundred lines of Dart that no test could reach without a
/// live backend. It now lives in `identity/routes.ts`, where every branch is
/// reachable from `vitest`, including the one that only fires when an identity
/// already belongs to somebody. That is exactly where the damage happens, and
/// exactly what was previously untestable.
///
/// So what is left here is three things: carrying the session, translating the
/// server's answer into the sum type the app is written against, and the one
/// decision that genuinely cannot be made on a server — which of two Google
/// flows this platform can run.
///
/// ## One session, two transports
///
/// The web holds its session in a first-party `HttpOnly` cookie, which
/// JavaScript cannot read and the browser attaches on its own. Android holds
/// the same session as a bearer token, because a background isolate woken by a
/// push has no cookie jar to read from. Better Auth issues both on every
/// response; which one this device keeps is decided in [StoredSession].
///
/// The token arrives in the `set-auth-token` **header**. The `token` field some
/// bodies carry is the unsigned first half of one and is not a credential —
/// sending it gets a 401 that looks exactly like a session problem.
final class BetterAuthService implements AuthService {
  BetterAuthService({
    required this.client,
    required this.sessions,
    StoredSession? restored,
    this.googleTokens,
    this.pending = const PendingIdentityRedirects(),
    this.leaveFor = navigateBrowser,
  }) : _current = restored?.account {
    // The restored account is a cache of the last answer the server gave, so
    // it is checked against the server straight away. Unawaited on purpose:
    // launching must not wait on a network round trip, and the correction —
    // a session that expired, or was signed out on another device — arrives on
    // the stream like any other change.
    unawaited(_revalidate());
  }

  /// The HTTP client every request goes through, shared with the ledger.
  ///
  /// Shared rather than built here, because the cookie jar and the bearer
  /// interceptor are properties of the connection: a second client would hold a
  /// second session, and the two would disagree the moment either changed.
  final api.OpensplitApi client;

  final SessionStore sessions;

  /// How this platform gets a Google ID token without leaving the app.
  ///
  /// Null on the web, and that null is the whole platform switch. Google
  /// Identity Services answers into an iframe or a popup, and neither survives
  /// the cross-origin isolation the local database needs, so the browser is
  /// sent to Google instead and comes back with a session already made.
  final GoogleTokenSource? googleTokens;

  final PendingIdentityRedirects pending;

  /// Sends the browser to Google, and does not come back.
  ///
  /// Injected so a test can watch where the flow would have gone: a redirect
  /// that really navigates ends the test process rather than failing it. The
  /// default throws on every platform but the web, which is the only one that
  /// signs in by leaving the page.
  final void Function(String url) leaveFor;

  Account? _current;
  final _changes = StreamController<Account?>.broadcast();

  Dio get _dio => client.dio;
  api.IdentityApi get _identity => client.getIdentityApi();

  @override
  Account? get currentUser => _current;

  @override
  Stream<Account?> authStateChanges() => _changes.stream;

  @override
  Future<Account> signInAnonymously() async {
    // Better Auth's own endpoint, not one of ours. The routes in
    // `identity/routes.ts` exist because three flows needed a decision made
    // around them; this one has nothing at stake — there is no session to
    // lose — so wrapping it would add a hop and no judgement.
    final response = await _dio.post<Map<String, Object?>>(
      '/api/auth/sign-in/anonymous',
      data: const <String, Object?>{},
    );

    final user = response.data?['user'];
    if (user is! Map) {
      throw StateError('Anonymous sign-in returned no account.');
    }

    final account = Account(
      id: user['id']! as String,
      isAnonymous: true,
      email: null,
      // Discarded deliberately. The anonymous plugin invents a display name,
      // and storing it would make "this profile has no name of its own" false
      // for every guest — which is the check that lets somebody claiming an
      // invite adopt the name a friend typed for them.
      displayName: null,
    );

    await _adopt(account, token: _tokenIn(response));
    return account;
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

    try {
      final response = await _identity.linkGoogle(
        googleIdentityRequest: api.GoogleIdentityRequest(
          idToken: credential.idToken,
          nonce: credential.nonce,
          allowSignIn: allowSignIn,
        ),
      );
      return AttemptCompleted(await _settle(response));
    } on DioException catch (error) {
      // The one refusal the caller has to act on: that Google account already
      // belongs to somebody, and signing in would leave this device's ledger
      // behind. The server refuses rather than doing it, because by the time
      // the session has been replaced it is too late to ask.
      if (_isAlreadyClaimed(error)) {
        throw IdentityAlreadyInUse(
          _messageIn(error) ??
              'That Google account already has an OpenSplit account of its '
                  'own.',
        );
      }
      rethrow;
    }
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
    final before = _current?.id;
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

    try {
      // Better Auth answers a browser flow with the URL to visit rather than a
      // session, and the two endpoints are the redirect equivalents of the
      // link-or-sign-in choice above: `link-social` keeps the session in hand,
      // `sign-in/social` replaces it.
      final response = await _dio.post<Map<String, Object?>>(
        intent == IdentityIntent.link
            ? '/api/auth/link-social'
            : '/api/auth/sign-in/social',
        data: {
          'provider': 'google',
          'callbackURL': googleRedirectUrl(Uri.base, returnTo),
        },
      );

      final url = response.data?['url'];
      if (url is! String) {
        throw StateError('Google sign-in did not answer with a URL to visit.');
      }
      leaveFor(url);
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

    final refusal = _refusalInCallbackUrl();
    if (refusal != null) {
      if (departure.intent == IdentityIntent.link) throw refusal;
      // A sign-in Google or the server refused outright. Nothing changed.
      return null;
    }

    // The browser came back carrying a cookie the page cannot read, so who the
    // session belongs to has to be asked rather than parsed.
    final account = await _revalidate();
    // Came back with no session at all: dismissed at Google, or the exchange
    // failed. Nothing happened and there is nothing to report.
    if (account == null) return null;

    return _outcomeFor(account, departure.previousUserId);
  }

  @override
  Future<EmailFlow> sendEmailCode(String email) async {
    final response = await _identity.startEmailSignIn(
      emailStartRequest: api.EmailStartRequest(email: email),
    );

    return switch (response.data?.flow) {
      api.EmailFlow.linkPending => EmailFlow.linkPending,
      // Includes the unknown-value sentinel. A flow this build cannot name is
      // safest read as the one that does not replace anything on its own — the
      // caller asks for a code either way, and the verify call carries the
      // server's own answer back rather than this guess.
      _ => EmailFlow.signInPending,
    };
  }

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    return _settle(
      await _identity.verifyEmailCode(
        emailVerifyRequest: api.EmailVerifyRequest(
          email: email,
          code: code,
          flow: flow == EmailFlow.linkPending
              ? api.EmailFlow.linkPending
              : api.EmailFlow.signInPending,
        ),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await _dio.post<void>('/api/auth/sign-out');
    } on DioException {
      // The device is signing out either way. A server that cannot be reached
      // keeps a session row nobody holds any more, which expires on its own;
      // refusing to clear the local half would leave somebody signed in to an
      // account they asked to leave.
    }

    await _adopt(null, token: null);
  }

  @override
  Future<void> deleteAccount() async {
    await client.getAccountApi().deleteAccount();

    // The session went with the account, so what is held here is already
    // worthless. Cleared rather than left to fail on the next request, which
    // would look like an outage rather than like the thing that was asked for.
    await _adopt(null, token: null);
  }

  // ------------------------------------------------------------------ session

  /// Asks the server who this device is, and adopts the answer.
  ///
  /// The correction to the cached account, and the only thing that ever clears
  /// a session this device did not knowingly end — an expired one, or a
  /// sign-out performed on another device.
  ///
  /// It never throws, and that is a requirement rather than a courtesy: the
  /// constructor starts one of these without awaiting it, so anything escaping
  /// here is an unhandled error in whatever zone happened to build the app.
  /// Only two answers are acted on — a session, and a 401 saying there is not
  /// one. Everything else, from no connectivity to a 500, leaves the cached
  /// account exactly as it was, because none of it is evidence that the person
  /// is signed out and the app renders from the local database either way.
  Future<Account?> _revalidate() async {
    final Response<Map<String, Object?>> response;
    try {
      response = await _dio.get<Map<String, Object?>>('/api/auth/get-session');
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) return _adopt(null, token: null);
      return _current;
    } catch (_) {
      return _current;
    }

    // A 200 with no user is Better Auth saying there is no session, which it
    // does rather than refusing — the endpoint answers "who is this" and
    // "nobody" is a valid answer to it.
    final user = response.data?['user'];
    if (user is! Map) return _adopt(null, token: null);

    return _adopt(
      _accountFrom(user),
      // Better Auth reissues on this call too, so a rotated token is picked up
      // here rather than only on a sign-in.
      token: _tokenIn(response) ?? sessions.read()?.token,
    );
  }

  /// One place the current account changes, so one place the stream fires.
  Future<Account?> _adopt(Account? account, {required String? token}) async {
    await sessions.write(
      account == null ? null : StoredSession(account: account, token: token),
    );

    _current = account;
    if (!_changes.isClosed) _changes.add(account);
    return account;
  }

  /// The server's answer, adopted and turned into the sum type.
  Future<IdentityOutcome> _settle(
    Response<api.IdentityOutcome> response,
  ) async {
    final body = response.data;
    if (body == null) throw StateError('Identity answered with no body.');

    final account = Account(
      id: body.account.id,
      isAnonymous: body.account.isAnonymous,
      email: body.account.email,
      displayName: body.account.displayName,
    );

    await _adopt(account, token: _tokenIn(response) ?? body.token);

    // `outcome` rather than a comparison of ids. Which case applies cannot be
    // inferred from which code path ran — signing in with Google using the
    // address an existing email account already owns lands on that same
    // account — so the server, which sees both ids, decides.
    return body.outcome == api.IdentityOutcomeOutcomeEnum.replaced
        ? SessionReplaced(
            account: account,
            // Non-null whenever the outcome is `replaced`; the fallback exists
            // because the contract has to spell the field on both branches for
            // the generated client to decode either. See `schemas/identity.ts`.
            strandedUserId: body.strandedUserId ?? account.id,
          )
        : SessionKept(account: account);
  }

  IdentityOutcome _outcomeFor(Account account, String? previousUserId) =>
      previousUserId == null || previousUserId == account.id
      ? SessionKept(account: account)
      : SessionReplaced(account: account, strandedUserId: previousUserId);

  Account _accountFrom(Map<Object?, Object?> user) => Account(
    id: user['id']! as String,
    isAnonymous: user['isAnonymous'] == true,
    email: _realEmail(user['email']),
    displayName: user['isAnonymous'] == true ? null : user['name'] as String?,
  );

  /// The address the anonymous plugin invents for a guest is never reported.
  ///
  /// It is never a real inbox, and somebody who saw
  /// `a1b2c3@anonymous.placeholder.invalid` on their account screen would
  /// reasonably think they had signed up with it.
  static String? _realEmail(Object? email) =>
      email is String && !email.endsWith('@anonymous.placeholder.invalid')
      ? email
      : null;

  /// The bearer token, from the header that actually carries one.
  ///
  /// Null on the web, where it is neither needed nor safe to keep: the browser
  /// already holds the session in a cookie its own JavaScript cannot read.
  static String? _tokenIn(Response<Object?> response) {
    if (kIsWeb) return null;
    final value = response.headers.value('set-auth-token');
    return value == null || value.isEmpty ? null : value;
  }

  static bool _isAlreadyClaimed(DioException error) =>
      error.response?.statusCode == 409 &&
      _codeIn(error) == 'identity_already_in_use';

  static String? _codeIn(DioException error) {
    final body = error.response?.data;
    final envelope = body is Map ? body['error'] : null;
    return envelope is Map ? envelope['code'] as String? : null;
  }

  static String? _messageIn(DioException error) {
    final body = error.response?.data;
    final envelope = body is Map ? body['error'] : null;
    return envelope is Map ? envelope['message'] as String? : null;
  }

  /// The already-claimed refusal, if the callback carried one.
  ///
  /// Better Auth puts a failed social callback's reason in the query string of
  /// the URL it sends the browser back to, so a refused return still has it in
  /// the address bar when this runs.
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

  /// Releases the change stream. Called when the provider holding this is.
  void dispose() => _changes.close();
}

/// Where Google should send the browser back to, given the page it left from.
///
/// Separate from the service and taking [base] rather than reading `Uri.base`
/// because this is the part that silently sends people to the wrong host, and a
/// global no test can set is a part no test can check.
///
/// Lands on `/welcome` carrying the real destination, rather than on the
/// destination itself, because the router already knows how to finish that
/// journey: a signed-in arrival at `/welcome` is sent to `from`, and
/// `safeReturnLocation` refuses anything that is not an internal route. So an
/// invite opened by somebody with no session ends on the invite, and a tampered
/// `from` cannot be turned into an open redirect.
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
