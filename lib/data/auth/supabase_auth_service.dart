import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/repositories/auth_service.dart';

/// Supabase-backed identity.
final class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final sb.SupabaseClient _client;

  Account? _toUser(sb.User? user) => user == null
      ? null
      : Account(
          id: user.id,
          isAnonymous: user.isAnonymous,
          email: user.email,
          displayName: user.userMetadata?['display_name'] as String?,
        );

  @override
  Account? get currentUser => _toUser(_client.auth.currentUser);

  @override
  Stream<Account?> authStateChanges() => _client.auth.onAuthStateChange.map(
    (event) => _toUser(event.session?.user),
  );

  @override
  Future<Account> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    final user = _toUser(response.user);
    if (user == null) {
      throw StateError('Anonymous sign-in returned no user');
    }
    return user;
  }

  @override
  Future<Account> linkGoogle({
    required String idToken,
    String? accessToken,
  }) async {
    // signInWithIdToken rather than the OAuth web redirect: the native flow is
    // one tap with no browser bounce, and it keeps the existing user id so an
    // anonymous session upgrades in place with nothing to migrate.
    final response = await _client.auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    final user = _toUser(response.user);
    if (user == null) {
      throw StateError('Google sign-in returned no user');
    }
    return user;
  }

  @override
  Future<void> sendEmailCode(String email) =>
      _client.auth.signInWithOtp(email: email);

  @override
  Future<Account> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: sb.OtpType.email,
    );
    final user = _toUser(response.user);
    if (user == null) {
      throw StateError('Code verification returned no user');
    }
    return user;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
