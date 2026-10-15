import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One short buzz as an irreversible action is confirmed.
void confirmedIrreversibly() {
  HapticFeedback.mediumImpact();
}

/// Keeps a rejected edit visible when access or data changes during a dialog.
Future<bool> saveWithFeedback(
  BuildContext context,
  Future<void> Function() save,
) async {
  if (!context.mounted) return false;
  try {
    await save();
    return true;
  } catch (error) {
    if (context.mounted) {
      final message = error is StateError ? error.message : '$error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save. $message')));
    }
    return false;
  }
}
