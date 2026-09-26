import 'package:flutter/services.dart';

/// One short buzz as an irreversible action is confirmed.
void confirmedIrreversibly() {
  HapticFeedback.mediumImpact();
}
