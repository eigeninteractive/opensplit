import 'dart:developer' as developer;

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a Play review, at most rarely, and never as a condition of
/// anything.
///
/// Three rules are worth stating because breaking any of them is a policy
/// violation rather than a matter of taste:
///
///  * No pre-filtering. Asking "are you enjoying OpenSplit?" and showing the
///    sheet only to the people who say yes is expressly forbidden, and it is
///    the pattern most apps use. So this asks everyone or nobody.
///  * No incentive, and nothing gated behind it.
///  * Nothing may depend on the outcome. Play's own quota means the sheet
///    usually does not appear at all, `requestReview` resolves either way, and
///    there is no way to learn whether anything was shown — so this returns
///    nothing and the caller carries on regardless.
///
/// Called from one place: a settle-up that just succeeded. That is the moment
/// the app has finished doing the thing it exists for, which is the only moment
/// an unprompted question is not an interruption. Never on launch, never after
/// an error.
class ReviewPrompt {
  /// [isAvailable] and [request] are injected rather than the [InAppReview]
  /// object itself, which has a private constructor and so cannot be faked.
  /// The part worth testing is the rate limit, not the platform channel.
  ReviewPrompt(
    this._prefs, {
    Future<bool> Function()? isAvailable,
    Future<void> Function()? request,
    DateTime Function()? clock,
  }) : _isAvailable = isAvailable ?? InAppReview.instance.isAvailable,
       _request = request ?? InAppReview.instance.requestReview,
       _clock = clock ?? DateTime.now;

  static const _key = 'review_last_asked';

  /// Play's own quota is roughly one prompt per user per month and it is
  /// enforced silently. Asking more often than this would spend it on somebody
  /// who has already been asked, and we would never know.
  static const _interval = Duration(days: 120);

  final SharedPreferences _prefs;
  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _request;
  final DateTime Function() _clock;

  /// True when enough time has passed and the platform offers the flow at all.
  Future<bool> isDue() async {
    final last = _prefs.getString(_key);
    if (last != null) {
      final asked = DateTime.tryParse(last);
      if (asked != null && _clock().difference(asked) < _interval) return false;
    }
    try {
      return await _isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Asks, and records that we did — whether or not anything was shown.
  ///
  /// Recorded first, on purpose. If the request throws, the failure is not the
  /// user's problem and re-asking on their next settle-up would be.
  Future<void> ask() async {
    await _prefs.setString(_key, _clock().toIso8601String());
    try {
      await _request();
    } catch (error) {
      developer.log(
        'The review sheet could not be shown',
        name: 'opensplit.review',
        level: 700,
        error: error,
      );
    }
  }
}
