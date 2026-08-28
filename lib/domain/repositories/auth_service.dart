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
///
/// A sum type rather than a pair of identifiers to compare. "Did this device's
/// ledger stay with the account" is the only question a caller has, and
/// answering it by diffing ids put that derivation at every call site while
/// exposing a value nothing else ever needed.
///
/// Which case applies cannot be inferred from which code path ran, and that is
/// why this is decided here rather than by the caller. Signing in with Google
/// using the address an existing email account already owns lands on *that
/// same account*: Supabase attaches the identity by matching a verified email,
/// so the sign-in branch ran and yet nothing moved. Only the resulting id
/// settles it.
sealed class IdentityOutcome {
  const IdentityOutcome({required this.account});

  final Account account;
}

/// Nothing on this device has to move: the account id did not change.
///
/// Covers three arrivals that look different and are not: linking to the
/// session in hand, a first sign-in with no session to lose, and the sign-in
/// that lands back on the account this device was already using.
final class SessionKept extends IdentityOutcome {
  const SessionKept({required super.account});
}

/// A different account holds the session now.
///
/// The ledger on this device stays with the account that wrote it, named by
/// [strandedUserId] — which local database was left behind is the only part of
/// the transition a caller can actually act on.
final class SessionReplaced extends IdentityOutcome {
  const SessionReplaced({required super.account, required this.strandedUserId});

  final String strandedUserId;
}

/// What starting a Google flow did.
///
/// Two platforms answer differently and the difference is not hideable: a
/// device that can mint an ID token in-process finishes here, and a browser
/// that has to leave the page cannot. Making that explicit in the return type
/// is what stops a caller awaiting a result that is never coming.
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
///
/// There is no result to await. It arrives on the next launch, from
/// [AuthService.resumeIdentityRedirect].
final class AttemptRedirected extends GoogleAttempt {
  const AttemptRedirected();
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
  /// [returnTo] is where the user should land afterwards, as an internal route
  /// — it survives the browser detour so an invite link opened by somebody with
  /// no session still ends on the invite. It is validated before use; an
  /// external destination is refused rather than followed.
  ///
  /// With no session this is simply a sign-in — the arrival is somebody who
  /// chose "continue with Google" on a device holding nothing, so there is
  /// nothing to weigh up and nothing to warn about.
  ///
  /// Reports [IdentityAlreadyInUse] when that Google account already belongs
  /// to an OpenSplit user and [allowSignIn] is false — the point at which the
  /// caller has to stop and say what signing in would cost, because by the time
  /// the session has been replaced it is too late to ask. Thrown from here
  /// where the flow completes in-process, and from [resumeIdentityRedirect]
  /// where it had to leave the page; the caller's answer is the same either
  /// way, which is why the refusal is one type and not two.
  ///
  /// With [allowSignIn] set, that same case signs in instead and the outcome
  /// reports it.
  Future<GoogleAttempt> continueWithGoogle({
    required String returnTo,
    bool allowSignIn = false,
  });

  /// Finishes a Google flow that left the page, if this launch is a return
  /// from one.
  ///
  /// Null when it is not, which is almost every launch. Throws
  /// [IdentityAlreadyInUse] on the same condition the in-process path throws
  /// it on — the difference is only that the refusal comes back from the
  /// browser rather than from a call, so it surfaces on arrival instead of
  /// inline. The caller asks the same question and calls [continueWithGoogle]
  /// again with [allowSignIn] set.
  ///
  /// Safe to call unconditionally at startup, and safe to call twice: the
  /// record it consumes is cleared as it is read, and an attempt abandoned at
  /// Google expires rather than waiting to fire against an unrelated launch.
  Future<IdentityOutcome?> resumeIdentityRedirect();

  /// Sends an eight-digit code to [email], attaching it to the current session if
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

  /// Deletes this account on the server, permanently.
  ///
  /// Not the same as [signOut] and not recoverable. The server drops the
  /// account, its profile, its sign-in identities and its push registrations,
  /// and deletes outright any group nobody else could ever read again.
  /// Memberships in shared groups become placeholders with the name intact, so
  /// co-members' balances and history are exactly as they were — the other
  /// side of a shared ledger is their record as much as it is this account's.
  ///
  /// Leaves the session alone. The caller decides what to do with the device,
  /// because wiping local storage and signing out is the same work sign-out
  /// already does.
  Future<void> deleteAccount();
}
