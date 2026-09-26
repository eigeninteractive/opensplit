/// A signed-in identity (`api.Account`) and what asking for an email code
/// started (`api.EmailFlow`): `linkPending` keeps the current user id,
/// `signInPending` replaces the session.
library;

export 'package:opensplit_api/opensplit_api.dart' show Account, EmailFlow;

import 'package:opensplit_api/opensplit_api.dart' show Account, EmailFlow;

/// Raised when an identity cannot be attached because somebody already has it.
class IdentityAlreadyInUse implements Exception {
  const IdentityAlreadyInUse(this.message);

  final String message;

  @override
  String toString() => 'IdentityAlreadyInUse: $message';
}

/// What attaching an identity did.
sealed class IdentityOutcome {
  const IdentityOutcome({required this.account});

  final Account account;
}

/// Nothing on this device has to move: the account id did not change.
final class SessionKept extends IdentityOutcome {
  const SessionKept({required super.account});
}

/// A different account holds the session now.
final class SessionReplaced extends IdentityOutcome {
  const SessionReplaced({required super.account, required this.strandedUserId});

  final String strandedUserId;
}

/// What starting a Google flow did.
sealed class GoogleAttempt {
  const GoogleAttempt();
}

/// Finished without leaving the app.
final class AttemptCompleted extends GoogleAttempt {
  const AttemptCompleted(this.outcome);

  final IdentityOutcome outcome;
}

/// The account picker was dismissed. Nothing happened, and nothing is pending.
final class AttemptCancelled extends GoogleAttempt {
  const AttemptCancelled();
}

/// The page is navigating to Google.
final class AttemptRedirected extends GoogleAttempt {
  const AttemptRedirected();
}

/// Identity, kept behind an interface like everything else that touches a
/// backend.
abstract interface class AuthService {
  Account? get currentUser;

  Stream<Account?> authStateChanges();

  /// Creates a real account with no credentials attached.
  Future<Account> signInAnonymously();

  /// Attaches Google to the current session, or signs in with it if there is no
  /// session to attach it to.
  Future<GoogleAttempt> continueWithGoogle({
    required String returnTo,
    bool allowSignIn = false,
  });

  /// Finishes a Google flow that left the page, if this launch is a return from
  /// one.
  Future<IdentityOutcome?> resumeIdentityRedirect();

  /// Sends an eight-digit code to [email], attaching it to the current session
  /// if the address is free and starting a sign-in if it is not.
  Future<EmailFlow> sendEmailCode(String email);

  /// Completes the flow [sendEmailCode] started. [flow] must be the value it
  /// returned: the two flows are different endpoints issuing different token
  /// types, and verifying against the wrong one fails with a message about an
  /// expired token that has nothing to do with what went wrong.
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  });

  Future<void> signOut();

  /// Deletes this account on the server, permanently.
  Future<void> deleteAccount();
}
