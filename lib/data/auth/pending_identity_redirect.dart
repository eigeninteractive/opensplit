import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which of the two operations a redirect was sent away to perform.
enum IdentityIntent {
  /// Attach the identity to the session already held. Same id, nothing moves.
  link,

  /// Authenticate as whoever owns the identity, replacing the session.
  signIn,
}

/// What a Google flow that left the page needs in order to finish on return.
class PendingIdentityRedirect {
  const PendingIdentityRedirect({
    required this.intent,
    required this.previousUserId,
    required this.returnTo,
    required this.startedAt,
  });

  factory PendingIdentityRedirect.fromJson(Map<String, Object?> json) =>
      PendingIdentityRedirect(
        intent: IdentityIntent.values.byName(json['intent']! as String),
        previousUserId: json['previousUserId'] as String?,
        returnTo: json['returnTo']! as String,
        startedAt: DateTime.parse(json['startedAt']! as String),
      );

  final IdentityIntent intent;

  /// Who held the session when the browser left, or null if nobody did.
  final String? previousUserId;

  /// Where to land afterwards, as an internal route.
  final String returnTo;

  final DateTime startedAt;

  /// How long a departure stays interesting.
  static const _lifetime = Duration(minutes: 10);

  bool get isExpired => DateTime.now().difference(startedAt) > _lifetime;

  Map<String, Object?> toJson() => {
    'intent': intent.name,
    'previousUserId': previousUserId,
    'returnTo': returnTo,
    'startedAt': startedAt.toIso8601String(),
  };
}

/// Where [PendingIdentityRedirect] lives while the browser is away.
class PendingIdentityRedirects {
  const PendingIdentityRedirects();

  static const _key = 'opensplit.pending_identity_redirect';

  Future<void> write(PendingIdentityRedirect pending) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(pending.toJson()));
  }

  /// Reads and clears in one step.
  Future<PendingIdentityRedirect?> take() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return null;
    await preferences.remove(_key);

    final PendingIdentityRedirect pending;
    try {
      pending = PendingIdentityRedirect.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on FormatException {
      // Written by an older build, or truncated. Nothing to finish.
      return null;
    }
    return pending.isExpired ? null : pending;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
