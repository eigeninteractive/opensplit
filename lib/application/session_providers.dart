import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/local/local_reset.dart';
import '../domain/repositories/auth_service.dart';
import 'backend_providers.dart';
import 'local_providers.dart';
import 'sync_providers.dart';

part 'session_providers.g.dart';

/// Where a refusal raised by a redirect waits until a screen can ask about it.
final googleRefusalProvider = Provider<ValueNotifier<IdentityAlreadyInUse?>>(
  (ref) => ValueNotifier<IdentityAlreadyInUse?>(null),
);

/// The current session, if any.
@Riverpod(keepAlive: true)
Stream<Account?> account(Ref ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) return Stream.value(null);
  return auth.authStateChanges();
}

/// Reports the current session, and reconciles this device's identity with it.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  /// Synchronous, deliberately. An async `build` would start in `AsyncLoading`,
  /// and the router would read a loading session as signed out and flash the
  /// welcome screen at everybody already signed in.
  @override
  Account? build() {
    final auth = ref.watch(authServiceProvider);
    // The initial answer remains synchronous. Later sign-outs, token expiry,
    // and account changes must still refresh it from the auth event stream.
    ref.watch(accountProvider);
    return auth?.currentUser;
  }

  /// Being a guest, chosen rather than assumed.
  Future<Account> continueAsGuest() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      throw StateError('This build has no backend, so it has no accounts.');
    }

    final user = auth.currentUser ?? await auth.signInAnonymously();
    state = user;
    return user;
  }

  /// Ends the session.
  Future<void> signOut() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    await forgetLocalLedger(ref.read(appDatabaseProvider), requireSynced: true);
    await auth.signOut();
    state = null;
  }

  /// Deletes the account, then leaves the device as a sign-out would.
  Future<void> deleteAccount() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    await auth.deleteAccount();
    await forgetLocalLedger(ref.read(appDatabaseProvider));
    await auth.signOut();
    state = null;
  }
}

/// Whether anybody is signed in, for the router to redirect on.
@Riverpod(keepAlive: true)
bool signedIn(Ref ref) => ref.watch(sessionControllerProvider) != null;

/// Attaching a real account to this device, and the sign-in it sometimes turns
/// out to be instead.
@Riverpod(keepAlive: true)
class AccountController extends _$AccountController {
  @override
  void build() {}

  /// How many expenses signing in as somebody else would leave behind.
  Future<int> entriesLeftBehind() =>
      ref.read(entryRepositoryProvider).countLiveEntries();

  AuthService _auth() {
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      throw StateError('This build has no backend, so it has no accounts.');
    }
    return auth;
  }

  Future<EmailFlow> sendEmailCode(String email) async {
    // Deliberately does NOT establish a session first.
    return _auth().sendEmailCode(email);
  }

  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    if (flow == EmailFlow.signInPending) await _checkPendingWrites();
    final outcome = await _auth().verifyEmailCode(
      email: email,
      code: code,
      flow: flow,
    );
    await _settle();
    return outcome;
  }

  /// Throws [IdentityAlreadyInUse] unless [allowSignIn], so the screen gets a
  /// chance to say what signing in would cost before the session is replaced.
  Future<GoogleAttempt> continueWithGoogle({
    required String returnTo,
    bool allowSignIn = false,
  }) async {
    // Before the call, and on the web that means before the page leaves: a
    // redirect has no moment on the way back at which refusing would still
    // help.
    if (allowSignIn) await _checkPendingWrites();
    // No session established first, for the same reason as sendEmailCode.
    final attempt = await _auth().continueWithGoogle(
      returnTo: returnTo,
      allowSignIn: allowSignIn,
    );
    // Nothing to settle for a flow that has not happened yet, or one the user
    // dismissed. The redirect settles on the way back, in [resumeGoogleRedirect].
    if (attempt is AttemptCompleted) await _settle();
    return attempt;
  }

  /// Finishes a Google flow that left the page, if this launch is a return.
  Future<IdentityOutcome?> resumeGoogleRedirect() async {
    final outcome = await _auth().resumeIdentityRedirect();
    if (outcome != null) await _settle();
    return outcome;
  }

  Future<void> _checkPendingWrites() async {
    if (ref.read(currentAccountIdProvider) == null) return;
    if (await ref.read(outboxQueueProvider).hasUnresolvedWrites()) {
      throw StateError(
        'Sync or resolve the changes on this device before switching accounts.',
      );
    }
  }

  /// Brings the device into line with whatever just happened to the session.
  Future<void> _settle() async {
    ref.invalidate(sessionControllerProvider);
    await ref.read(syncControllerProvider.notifier).syncAll();
  }
}
