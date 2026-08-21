import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';

/// Asks the user to attach a real account, once they have something to lose.
///
/// The copy is blunt on purpose. An anonymous account lives on exactly one
/// device with no recovery path whatsoever, and on the web it is destroyed by
/// clearing site data — something people do routinely and without expecting to
/// lose anything. Softening that wording would make the eventual loss our
/// fault.
///
/// Shown after the third entry, never as a wall, and dismissible.
class LinkAccountPrompt extends ConsumerWidget {
  const LinkAccountPrompt({super.key});

  /// Entries recorded before it is worth interrupting anyone.
  static const int threshold = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final count = ref.watch(totalEntryCountProvider).value ?? 0;
    final dismissed = ref.watch(promptDismissedProvider);

    if (account == null || !account.isAnonymous) return const SizedBox.shrink();
    if (count < threshold || dismissed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your expenses only exist on this device',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              kIsWeb
                  ? 'There is no account attached, so nothing can be recovered. '
                        'Clearing your browser data will delete all of it, '
                        'permanently.'
                  : 'There is no account attached, so nothing can be recovered '
                        'if you lose this phone or reinstall the app.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(promptDismissedProvider.notifier).dismiss(),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => context.go('/settings'),
                  child: const Text('Save my account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the prompt has been dismissed this session.
///
/// Deliberately not persisted: the warning stays true, and the risk grows with
/// every expense added. It reappears next launch.
class PromptDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final promptDismissedProvider = NotifierProvider<PromptDismissed, bool>(
  PromptDismissed.new,
);
