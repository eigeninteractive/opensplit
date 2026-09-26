import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../config.dart';

/// Offers notifications at the one moment they obviously matter.
Future<void> offerNotifications(BuildContext context, WidgetRef ref) async {
  if (!hasPush) return;

  final preference = ref.read(notificationPreferenceProvider.notifier);
  // Already on, or already asked and declined. Neither is worth re-raising:
  // Settings has a switch for anyone who changes their mind.
  if (preference.hasBeenAsked()) return;

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
