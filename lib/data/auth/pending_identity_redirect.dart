import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which of the two operations a redirect was sent away to perform.
///
/// Decided before leaving, and that is the whole point. The in-process flow can
/// attempt a link, catch the refusal and offer a sign-in inside one call; a
/// flow that navigates away cannot recover mid-flight, so the intent has to be
/// settled while the old session is still in hand and carried across.
enum IdentityIntent {
  /// Attach the identity to the session already held. Same id, nothing moves.
  link,

  /// Authenticate as whoever owns the identity, replacing the session.
  signIn,
}

/// What a Google flow that left the page needs in order to finish on return.
///
/// Everything here is knowable only *before* the detour and unknowable after
/// it, which is the test for what belongs in this record. The app cold-starts
/// on the way back — no widget state, no provider cache, and a session that is
/// already the new one — so anything the resume has to compare against must
/// have been written down first.
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
  ///
  /// Private to the resume, deliberately. Comparing it against the id that
  /// comes back is how [SessionKept] and [SessionReplaced] are told apart, but
  /// that comparison is the data layer's job and no caller should ever see
  /// this value.
  final String? previousUserId;

  /// Where to land afterwards, as an internal route.
  final String returnTo;

  final DateTime startedAt;

  /// How long a departure stays interesting.
  ///
  /// Someone who reaches Google and closes the tab leaves this behind. Without
  /// an expiry it would sit there and fire against an unrelated launch days
  /// later, reporting an outcome for a flow the user has long forgotten.
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
///
/// `SharedPreferences` rather than anything in memory, for the obvious reason:
/// on the web this is `localStorage`, same origin, and it is the only thing
/// that survives the navigation. It sits beside the session GoTrue persists
/// through the same mechanism, so a browser that loses one loses both and the
/// flow fails closed rather than half-completing.
class PendingIdentityRedirects {
  const PendingIdentityRedirects();

  static const _key = 'opensplit.pending_identity_redirect';

  Future<void> write(PendingIdentityRedirect pending) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(pending.toJson()));
  }

  /// Reads and clears in one step.
  ///
  /// Consumed rather than merely read, so a resume that throws on its way to
  /// the caller cannot leave the record behind to fire a second time. Returns
  /// null when there is nothing pending or when what was there had expired.
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
