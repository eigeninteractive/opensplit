import 'package:flutter/services.dart';

/// One short buzz as an irreversible action is confirmed.
///
/// The rule it establishes is worth more than any single call site: the app
/// speaks to your hand exactly once, at the moment something happens that
/// cannot be taken back. Sign out, leave a group, delete an expense, remove
/// somebody, delete an account. Nothing else in the app vibrates, so the
/// sensation never becomes background noise and never has to be learned.
///
/// [HapticFeedback.mediumImpact] rather than the heavier or lighter ones.
/// Light is the tick a picker makes and reads as navigation; heavy is what a
/// failure or a long-press reads as. Medium is the one that lands as "that
/// happened".
///
/// Deliberately fire-and-forget. This returns a Future only because the
/// platform channel does, and awaiting it would put a round trip to the OS in
/// front of closing a dialog. A device with no vibrator, a browser, or a user
/// who has turned haptics off all resolve it as a no-op, which is why there is
/// nothing here to check first.
void confirmedIrreversibly() {
  HapticFeedback.mediumImpact();
}
