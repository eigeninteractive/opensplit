import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/auth_service.dart';

/// The session as it survives a restart: a cache of the server's last answer,
/// readable synchronously so a signed-in launch never flashes the welcome
/// screen. [BetterAuthService] revalidates it straight away.
class StoredSession {
  const StoredSession({required this.account, required this.token});

  /// The account's own fields plus `token`, flat, as older builds wrote it.
  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
    account: Account.fromJson(json),
    token: json['token'] as String?,
  );

  final Account account;

  /// The bearer token on Android, where a background isolate has no cookie
  /// jar. Never stored on the web, whose HttpOnly cookie JavaScript cannot read.
  final String? token;

  Map<String, Object?> toJson() => {
    ...account.toJson(),
    if (!kIsWeb) 'token': token,
  };
}

class SessionStore {
  const SessionStore(this._preferences);

  final SharedPreferences _preferences;

  static const _key = 'opensplit.session';

  /// Synchronous, so it needs an already loaded [SharedPreferences].
  StoredSession? read() {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Unreadable: revalidation produces the real answer a moment later.
      return null;
    }
  }

  Future<void> write(StoredSession? session) async {
    if (session == null) {
      await _preferences.remove(_key);
      return;
    }
    await _preferences.setString(_key, jsonEncode(session.toJson()));
  }
}

/// The session a background isolate may use: read-only, Android-only, and
/// only once notifications have been asked for.
Future<StoredSession?> readBackgroundSession() async {
  if (kIsWeb) return null;

  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  if (preferences.getBool('notifications_requested') != true) return null;

  final session = SessionStore(preferences).read();
  return session?.token == null ? null : session;
}
