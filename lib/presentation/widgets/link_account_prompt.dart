import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/session_providers.dart';

/// Asks a guest to attach a real account as soon as they are in any group:
/// from then on the server holds something only this session can reach, and
/// somebody who joined through an invite and only reads balances has as much
/// to lose as somebody recording every expense.
class LinkAccountPrompt extends ConsumerWidget {
  const LinkAccountPrompt({super.key, this.padding = EdgeInsets.zero});

  /// Applied only when there is something to show, so that a prompt nobody
  /// needs does not leave a gap where a caller placed it in a column.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    if (account == null || !account.isAnonymous) return const SizedBox.shrink();

    final groups = ref.watch(groupListingsProvider).value ?? const [];
    final dismissed = ref.watch(promptDismissedProvider);
    if (groups.isEmpty || dismissed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: padding,
      child: MaterialBanner(
        backgroundColor: scheme.tertiaryContainer,
        // Material's own banner padding assumes a single line of content beside
        // the icon.
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
            onPressed: () => context.push('/account/save'),
            child: const Text('Save my account'),
          ),
        ],
      ),
    );
  }
}

/// Whether the prompt has been dismissed this session.
class PromptDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final promptDismissedProvider = NotifierProvider<PromptDismissed, bool>(
  PromptDismissed.new,
);
