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

/// Identity, kept behind an interface like everything else that touches a
/// backend.
///
/// Anonymous is the default entry path, not a fallback. Most people arrive
/// because a friend added them as a placeholder and sent a link, and a signup
/// wall at that moment is where they leave. Upgrading later preserves the same
/// user id, so nothing has to be migrated when they do.
abstract interface class AuthService {
  Account? get currentUser;

  Stream<Account?> authStateChanges();

  /// Creates a real account with no credentials attached.
  Future<Account> signInAnonymously();

  /// Attaches Google to the current session, keeping the same user id.
  Future<Account> linkGoogle({required String idToken, String? accessToken});

  /// Sends a six-digit code.
  ///
  /// A code, not a magic link: magic links open in whichever browser the mail
  /// app prefers, lose the app's context entirely, and are routinely consumed
  /// by corporate mail scanners before the recipient ever sees them.
  Future<void> sendEmailCode(String email);

  Future<Account> verifyEmailCode({
    required String email,
    required String code,
  });

  Future<void> signOut();
}
