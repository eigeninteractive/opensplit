import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';

/// Asks the user to attach a real account, once they have something to lose.
///
/// The copy is blunt on purpose. The guest's data synchronizes, but its only
/// credential lives on this device. Clearing site data or losing the phone
/// strands the server account rather than deleting it.
///
/// Built like [UnsyncedChangesBanner] and coloured differently on purpose. The
/// two are the only banners in the app and they say different kinds of thing:
/// the error-coloured one means something is already wrong, this one means
/// something is about to be. Both now lead with a heading, because the version
/// of this that did not was three lines of body text in a pastel box and read
/// as decoration.
///
/// Shown after the third entry, never as a wall, and dismissible.
class LinkAccountPrompt extends ConsumerWidget {
  const LinkAccountPrompt({super.key, this.padding = EdgeInsets.zero});

  /// Applied only when there is something to show, so that a prompt nobody
  /// needs does not leave a gap where a caller placed it in a column.
  final EdgeInsets padding;

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
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: padding,
      child: MaterialBanner(
        backgroundColor: scheme.tertiaryContainer,
        // Material's own banner padding assumes a single line of content
        // beside the icon. This has a heading and a paragraph, and the default
        // leaves the text crowding the top edge and the actions crowding the
        // bottom one.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        dividerColor: Colors.transparent,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onTertiaryContainer,
        ),
        leading: Icon(
          Icons.warning_amber_rounded,
          color: scheme.onTertiaryContainer,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Protect access to this guest account',
              style: text.titleSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kIsWeb
                  ? 'Your groups synchronize, but this browser holds the only '
                        'way back in. Clearing its data can leave you unable to '
                        'reach the guest account.'
                  : 'Your groups synchronize, but this phone holds the only '
                        'way back in. Losing it or reinstalling can leave you '
                        'unable to reach the guest account.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(promptDismissedProvider.notifier).dismiss(),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onTertiaryContainer,
            ),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => context.go('/account'),
            child: const Text('Save my account'),
          ),
        ],
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
