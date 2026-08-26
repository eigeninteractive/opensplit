/// A signed-in identity.
///
/// Named Account rather than the more obvious AuthUser because the backend SDK
/// exports a class by that name, and an unqualified collision in generated code
/// resolves to whichever the analyzer reaches first.
class Account {
  const Account({
    required this.id,
    required this.isAnonymous,
    this.email,
    this.displayName,
  });

  final String id;

  /// True for a session created by [AuthService.signInAnonymously].
  ///
  /// Anonymous means one device and no recovery: on the web, clearing site data
  /// destroys the account permanently. It also gates destructive actions
  /// server-side, via the `is_anonymous` claim in the JWT.
  final bool isAnonymous;

  final String? email;
  final String? displayName;
}

/// What asking for an email code actually started.
///
/// Attaching an address to the session you already have and signing in to an
/// account that already exists are different endpoints issuing different token
/// types, and verifying a code against the wrong one fails with a message
/// about an expired token that has nothing to do with what went wrong. So the
/// answer travels back with the code rather than being guessed at afterwards.
enum EmailFlow {
  /// Attached outright, with no code — this deployment does not confirm email
  /// changes. Nothing further to do, and nothing to prompt for.
  ///
  /// OpenSplit's own `config.toml` turns confirmations on, because without
  /// them anybody can claim an address they do not own. A self-hosted
  /// deployment may not have, and a screen that then waits forever for a code
  /// is a worse answer than handling it.
  linked,

  /// A code was sent. Verifying it keeps the current user id, so every row on
  /// this device still belongs to it.
  linkPending,

  /// The address already had an account, so there was nothing to attach it to
  /// and a sign-in code was sent instead. Verifying it REPLACES the session,
  /// and anything recorded anonymously on this device stays with the anonymous
  /// account that recorded it.
  signInPending,
}

/// Raised when an identity cannot be attached because somebody already has it.
///
/// Thrown rather than quietly signing in, because those are opposite outcomes
/// from the user's point of view: one keeps everything on this device, the
/// other leaves it behind. The caller catches this, says so plainly, and only
/// then asks again with signing in permitted.
class IdentityAlreadyInUse implements Exception {
  const IdentityAlreadyInUse(this.message);

  final String message;

  @override
  String toString() => 'IdentityAlreadyInUse: $message';
}

/// What attaching an identity did.
class IdentityOutcome {
  const IdentityOutcome({required this.account, required this.previousUserId});

  final Account account;

  /// Who held the session immediately before, or null if nobody did.
  final String? previousUserId;

  /// True when nothing on this device has to move.
  ///
  /// Derived from the ids rather than from which code path ran, because those
  /// two answers are not always the same. Signing in with Google using the
  /// address an existing email account already owns lands on *that same
  /// account*: Supabase attaches the new identity by matching a verified email.
  /// The sign-in branch ran, but the user id never changed, and wiping the
  /// device there would delete data that was never orphaned.
  ///
  /// A first sign-in with no prior session is the same story for a different
  /// reason: there was no session to lose.
  bool get keptTheSession =>
      previousUserId == null || previousUserId == account.id;
}

/// Identity, kept behind an interface like everything else that touches a
/// backend.
///
/// Being a guest is a choice somebody makes, not a state they are put in.
///
/// It used to be the latter: every launch with no session signed in
/// anonymously, silently, before the user had expressed any intent at all.
/// That quietly broke the most common arrival there is. Someone who already had
/// an account and tapped a friend's invite link had the slot claimed by a
/// throwaway account, the single-use token spent, and no way in afterwards —
/// signing in gave them a different user id, the member row still pointed at
/// the anonymous one, and the group refused a second slot for the same person.
/// The only repair was the group's owner issuing a fresh link.
///
/// So a session is now established because somebody asked for one, by one of
/// three routes offered together: Google, an email code, or being a guest.
/// Guests remain first class — no wall, nothing gated, and an invite is shown
/// before it is claimed — but the app no longer decides who you are before
/// asking.
///
/// ## Linking is not signing in
///
/// The distinction runs through every method here and it is the one that was
/// got wrong. Attaching Google or an email address to an anonymous session has
/// to *link* — same user id, same rows, nothing to migrate. `signInWithIdToken`
/// and `signInWithOtp` do not link: they authenticate, which means they sign
/// in as a different user and leave the anonymous one behind holding every
/// group the person had already created. The account is then a stranger to its
/// own data, and every push is refused by row-level security.
///
/// So the linking calls are [continueWithGoogle] and [sendEmailCode] /
/// [verifyEmailCode], each of which tries to link first and only falls back to
/// signing in when the identity demonstrably belongs to somebody already —
/// reporting which of the two happened, because the caller has to say so.
abstract interface class AuthService {
  Account? get currentUser;

  Stream<Account?> authStateChanges();

  /// Creates a real account with no credentials attached.
  Future<Account> signInAnonymously();

  /// Attaches Google to the current session, or signs in with it if there is
  /// no session to attach it to.
  ///
  /// With no session this is simply a sign-in — the arrival is somebody who
  /// chose "continue with Google" on a device holding nothing, so there is
  /// nothing to weigh up and nothing to warn about.
  ///
  /// Throws [IdentityAlreadyInUse] when that Google account already belongs to
  /// an OpenSplit user and [allowSignIn] is false — the point at which the
  /// caller has to stop and say what signing in would cost, because by the time
  /// the session has been replaced it is too late to ask.
  ///
  /// With [allowSignIn] set, that same case signs in instead and the returned
  /// outcome reports it.
  Future<IdentityOutcome> continueWithGoogle({
    required String idToken,
    String? accessToken,
    bool allowSignIn = false,
  });

  /// Sends a six-digit code to [email], attaching it to the current session if
  /// the address is free and starting a sign-in if it is not.
  ///
  /// A code, not a magic link: magic links open in whichever browser the mail
  /// app prefers, lose the app's context entirely, and are routinely consumed
  /// by corporate mail scanners before the recipient ever sees them. That
  /// requires an email template carrying `{{ .Token }}` — the stock Supabase
  /// ones do not, and against those no code is ever sent. See
  /// `supabase/templates/README.md`.
  ///
  /// The returned flow must be handed back to [verifyEmailCode], unless it is
  /// [EmailFlow.linked], which is already finished.
  Future<EmailFlow> sendEmailCode(String email);

  /// Completes the flow [sendEmailCode] started. [flow] must be the value it
  /// returned, and must not be [EmailFlow.linked].
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  });

  Future<void> signOut();
}
