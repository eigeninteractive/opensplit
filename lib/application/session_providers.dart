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
///
/// The in-process flow throws [IdentityAlreadyInUse] to the widget that made
/// the call, which is still on screen to catch it. A redirect has no such
/// caller: the refusal arrives on a fresh launch, before any screen has built.
/// So it is parked here by whoever resumes and collected by the screen the
/// user was returned to.
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
///
/// It does NOT create one. Signing in anonymously the moment the app opened was
/// the app deciding who somebody was before asking, and it broke the arrival it
/// was meant to protect: a person who already had an account and tapped an
/// invite link had the slot claimed by a throwaway account and the single-use
/// token spent, with no way in afterwards. Every session now begins because
/// somebody chose Google, an email code, or [continueAsGuest].
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  /// Synchronous, and that is the whole point.
  ///
  /// This used to be `Future<Account?> build() async` with no `await` in it —
  /// a synchronous read dressed as an asynchronous one. Riverpod honours the
  /// signature rather than the body, so the first state was always
  /// `AsyncLoading`, and every reader had to decide what a loading session
  /// meant. The router decided it meant "signed out" and navigated, which put
  /// a flash of the welcome screen in front of everybody who was already
  /// signed in, on every load.
  ///
  /// `Supabase.initialize` restores the stored session in `main` before
  /// `runApp`, so by the time anything can ask, `currentUser` answers from
  /// memory. There is no moment where the answer is unknown, so there is no
  /// state to represent one.
  @override
  Account? build() {
    final auth = ref.watch(authServiceProvider);
    // The initial answer remains synchronous. Later sign-outs, token expiry,
    // and account changes must still refresh it from the auth event stream.
    ref.watch(accountProvider);
    return auth?.currentUser;
  }

  /// Being a guest, chosen rather than assumed.
  ///
  /// A real account with no credential attached: same uid, same rows, same
  /// row-level security as anybody else. What it does not have is any way back
  /// after losing the device, which is why it is offered as one of three
  /// choices instead of happening on its own.
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
  ///
  /// The local ledger is deleted rather than left behind. Keying the database
  /// by account already makes it unreachable to anybody else who signs in
  /// here — that is a correctness guarantee and it holds regardless — but a
  /// shared device is a privacy question as well as a correctness one, and
  /// "sign out" has to mean the next person cannot read what the last one
  /// spent. It costs a re-sync on return, which is the cheap half of the
  /// trade.
  Future<void> signOut() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    await forgetLocalLedger(ref.read(appDatabaseProvider), requireSynced: true);
    await auth.signOut();
    state = null;
  }

  /// Deletes the account, then leaves the device as a sign-out would.
  ///
  /// The server call goes first and is not caught. If it fails there is nothing
  /// to clean up locally and the account still exists, so wiping the device
  /// would destroy the only copy of data the server still holds under an
  /// account the user believes is gone — the one outcome worse than the delete
  /// simply not working.
  ///
  /// It also has to happen while the session is still valid: the RPC is
  /// authorised by `auth.uid()`, so signing out first would leave nothing to
  /// identify the account by.
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
///
/// A named projection rather than an inline `!= null` so the router refreshes
/// on the answer changing rather than on the account object changing: Riverpod
/// only notifies when the computed value differs, and most session updates do
/// not flip this bool.
@Riverpod(keepAlive: true)
bool signedIn(Ref ref) => ref.watch(sessionControllerProvider) != null;

/// Attaching a real account to this device, and the sign-in it sometimes turns
/// out to be instead.
///
/// The two outcomes are opposites and the difference is the whole reason this
/// exists rather than the screen calling [AuthService] directly. Linking keeps
/// the user id, so every group, member and expense on this device stays exactly
/// where it is. Signing in as an account that already exists replaces the
/// session, and those rows are then unreachable: the server holds them under
/// the anonymous user that wrote them, and row-level security refuses every
/// write made under the new one. Keeping them on screen would produce a group
/// list where some rows sync and some never can, with nothing to say which.
///
/// So a sign-in wipes the device first — after the screen has said so and been
/// answered — and re-syncs from the server as the account that now holds it.
@Riverpod(keepAlive: true)
class AccountController extends _$AccountController {
  @override
  void build() {}

  /// How many expenses signing in as somebody else would leave behind.
  ///
  /// Used to make the warning specific. "You will lose what is on this device"
  /// is ignorable; "the 34 expenses on this device stay with the anonymous
  /// account" is not.
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
    // Deliberately does NOT establish a session first. With one, this attaches
    // the address and keeps every group on the device; without one, it is a
    // sign-in, or a sign-up for an address nobody has yet. Minting a guest
    // account here would put the caller in the first case when they asked for
    // the second, which is how somebody ends up owning an anonymous account
    // they never wanted.
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
    // help. Only signing in can strand writes, which is what allowSignIn
    // gates.
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
  ///
  /// Null when it is not. Throws [IdentityAlreadyInUse] on the refusal the
  /// in-process path throws inline, so the screen asks the same question and
  /// calls [continueWithGoogle] again with [allowSignIn] set.
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
  ///
  /// Almost nothing, now. There is no ledger to wipe and no id to repoint:
  /// the database is named after the account, so invalidating the session is
  /// enough to close one account's file and open the other's. What is left is
  /// asking the server what this account has.
  Future<void> _settle() async {
    ref.invalidate(sessionControllerProvider);
    await ref.read(syncControllerProvider.notifier).syncAll();
  }
}
