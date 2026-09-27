import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:opensplit_api/opensplit_api.dart' show Account;
import 'package:shared_preferences/shared_preferences.dart';

/// The session as it survives a restart: a cache of the server's last answer,
/// readable synchronously so a signed-in launch never flashes the welcome
/// screen. [BetterAuthService] revalidates it straight away.
class StoredSession {
  const StoredSession({required this.account, required this.token});

  final Account account;

  /// The bearer token on Android, where a background isolate has no cookie
  /// jar. Never stored on the web, whose HttpOnly cookie JavaScript cannot read.
  final String? token;
}

/// Where the bearer token is kept: a credential, so not beside the account.
abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String? token);
}

/// The Android Keystore, through `flutter_secure_storage`. Its file is left out
/// of backups (`android/app/src/main/res/xml`), since a restored copy could not
/// be decrypted on another device anyway; a token it cannot read comes back as
/// none, which is signed out.
class SecureTokenVault implements TokenVault {
  const SecureTokenVault();

  static const _key = 'opensplit.session.token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) => token == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: token);
}

/// A token for this process only: the web, which keeps none, and tests.
class MemoryTokenVault implements TokenVault {
  MemoryTokenVault([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String? token) async => _token = token;
}

/// The account in preferences, for a synchronous read at launch, and the token
/// in a [TokenVault], read once by [load] and held in memory after that.
class SessionStore {
  SessionStore._(this._preferences, this._vault, this._token);

  /// Reads the token before the first frame, so [read] stays synchronous.
  static Future<SessionStore> load(
    SharedPreferences preferences, {
    TokenVault? vault,
  }) async {
    final chosen = vault ?? platformTokenVault();
    return SessionStore._(preferences, chosen, await chosen.read());
  }

  final SharedPreferences _preferences;
  final TokenVault _vault;
  String? _token;

  static const _key = 'opensplit.session';

  StoredSession? read() {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final account = Account.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return StoredSession(account: account, token: _token);
    } on Object {
      // Unreadable: revalidation produces the real answer a moment later.
      return null;
    }
  }

  Future<void> write(StoredSession? session) async {
    final token = kIsWeb ? null : session?.token;
    // The token first: an account stored without its credential reads as a
    // session the server will refuse, and revalidation signs it out.
    await _vault.write(token);
    _token = token;
    if (session == null) {
      await _preferences.remove(_key);
      return;
    }
    await _preferences.setString(_key, jsonEncode(session.account.toJson()));
  }
}

/// The Keystore on Android; nothing on the web, whose session is a cookie.
TokenVault platformTokenVault() =>
    kIsWeb ? MemoryTokenVault() : const SecureTokenVault();

/// The session a background isolate may use: read-only, Android-only, and
/// only once notifications have been asked for.
Future<StoredSession?> readBackgroundSession() async {
  if (kIsWeb) return null;

  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  if (preferences.getBool('notifications_requested') != true) return null;

  final session = (await SessionStore.load(preferences)).read();
  return session?.token == null ? null : session;
}
