import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/auth_service.dart';

/// The session this device holds, as it survives a restart.
///
/// ## Why the account is cached and not just fetched
///
/// [SessionController] reads `currentUser` synchronously, and that is
/// deliberate: an asynchronous read there put a flash of the welcome screen in
/// front of everybody who was already signed in, on every launch, because
/// Riverpod's first state for a `Future` is always loading and the router read
/// loading as signed out.
///
/// So the answer has to be in hand before `runApp`, and a network round trip
/// cannot be. What is stored is a cache of the last answer the server gave;
/// [BetterAuthService] revalidates it against the server immediately afterwards
/// and emits a correction if it has changed. The server remains the authority
/// on every request — nothing here grants anything.
class StoredSession {
  const StoredSession({required this.account, required this.token});

  factory StoredSession.fromJson(Map<String, Object?> json) => StoredSession(
    account: Account(
      id: json['id']! as String,
      isAnonymous: json['isAnonymous']! as bool,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
    ),
    token: json['token'] as String?,
  );

  final Account account;

  /// The bearer token, on the platforms that have to carry one.
  ///
  /// Null on the web, and never written there. The browser holds the session in
  /// a first-party `HttpOnly` cookie that JavaScript cannot read, which is what
  /// stops a compromised dependency stealing it — copying the same session into
  /// `localStorage` would hand that protection straight back.
  ///
  /// Android has no cookie jar a background isolate can reach, so there the
  /// token is the only way a push handler can sync before it draws a
  /// notification.
  final String? token;

  Map<String, Object?> toJson() => {
    'id': account.id,
    'isAnonymous': account.isAnonymous,
    'email': account.email,
    'displayName': account.displayName,
    if (!kIsWeb) 'token': token,
  };
}

/// Where [StoredSession] lives between launches.
class SessionStore {
  const SessionStore(this._preferences);

  final SharedPreferences _preferences;

  static const _key = 'opensplit.session';

  /// Synchronous, which is the whole reason this takes a loaded
  /// [SharedPreferences] rather than fetching one.
  StoredSession? read() {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;

    try {
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      return null;
    } on TypeError {
      // Written by an older build with a different shape. Nothing to restore,
      // and revalidation will produce the real answer a moment later.
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

/// The session a background isolate is allowed to use.
///
/// A separate entry point rather than [SessionStore.read] because the isolate
/// has different rules. It never refreshes or rotates anything — the foreground
/// owns the session — and it only runs at all once notifications have been
/// asked for, which is the flag checked here.
///
/// Returns null on the web, where there is no background isolate and no stored
/// token to give one.
Future<StoredSession?> readBackgroundSession() async {
  if (kIsWeb) return null;

  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  if (preferences.getBool('notifications_requested') != true) return null;

  final session = SessionStore(preferences).read();
  return session?.token == null ? null : session;
}
