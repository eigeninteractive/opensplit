import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/session_providers.dart';
import 'inline_notice.dart';

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

    return Padding(
      padding: padding,
      child: InlineNotice(
        icon: Icons.lock_outline,
        title: 'Protect access to this guest account',
        message: kIsWeb
            ? 'Clearing browser data can lock you out. Add email or Google '
                  'for recovery.'
            : 'Losing this phone or reinstalling can lock you out. Add email '
                  'or Google for recovery.',
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(promptDismissedProvider.notifier).dismiss(),
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
