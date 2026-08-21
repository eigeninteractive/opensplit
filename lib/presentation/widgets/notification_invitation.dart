import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../config.dart';

/// Offers notifications at the one moment they obviously matter.
///
/// Called after someone shares an invite — the point at which this stops being
/// a private ledger and becomes a shared one, and "tell me when they add
/// something" first means anything. Asking at launch instead would spend
/// Android's very small budget of permission dialogs on a user who has not yet
/// created a group, and a second refusal there makes the system dialog stop
/// appearing at all.
///
/// A rationale is shown first, in-app, where a "Not now" costs nothing. Only
/// "Yes" reaches the OS prompt, so the expensive dialog is only ever spent on
/// someone who has already said they want it.
Future<void> offerNotifications(BuildContext context, WidgetRef ref) async {
  if (!hasPush) return;

  final preference = ref.read(notificationPreferenceProvider.notifier);
  // Already on, or already asked and declined. Neither is worth re-raising:
  // Settings has a switch for anyone who changes their mind.
  if (preference.hasBeenAsked) return;

  final wanted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_none),
      title: const Text('Get told when they add something?'),
      content: const Text(
        'Now that someone else is in this group, OpenSplit can let you know '
        'when they add an expense or settle up.\n\n'
        'The server only ever sends an id. The notification text is put '
        'together on your device, so nothing about what you spend leaves it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes, notify me'),
        ),
      ],
    ),
  );

  if (wanted != true) {
    // Recorded as asked-and-declined so this never reappears uninvited.
    await preference.markDeclined();
    return;
  }

  final granted = await preference.enable();
  if (granted || !context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Android did not grant permission. You can turn notifications on for '
        'OpenSplit in system settings.',
      ),
    ),
  );
}
