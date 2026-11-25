import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/backend_providers.dart';
import '../../application/ledger_providers.dart';
import '../../application/session_providers.dart';
import 'inline_notice.dart';

/// Offers account recovery to guests, either as a Home reminder or in Account.
class LinkAccountPrompt extends ConsumerWidget {
  /// A dismissible reminder once the guest has a group worth recovering.
  const LinkAccountPrompt({super.key, this.padding = EdgeInsets.zero})
    : _isReminder = true;

  /// The action in Account is available even after dismissing the reminder.
  const LinkAccountPrompt.account({super.key, this.padding = EdgeInsets.zero})
    : _isReminder = false;

  final bool _isReminder;

  /// Applied only when there is something to show, so that a prompt nobody
  /// needs does not leave a gap where a caller placed it in a column.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    if (account == null || !account.isAnonymous) return const SizedBox.shrink();

    if (_isReminder) {
      final groups = ref.watch(groupListingsProvider).value ?? const [];
      final dismissed = ref.watch(promptDismissedProvider);
      if (groups.isEmpty || dismissed) return const SizedBox.shrink();
    }

    return Padding(
      padding: padding,
      child: InlineNotice(
        icon: Icons.lock_outline,
        title: 'Save access to your groups',
        message:
            'Add Google or email to recover your account on another device.',
        actions: [
          if (_isReminder)
            TextButton(
              onPressed: () =>
                  ref.read(promptDismissedProvider.notifier).dismiss(),
              child: const Text('Not now'),
            ),
          FilledButton(
            onPressed: ref.watch(requiresAppUpdateProvider)
                ? null
                : () => context.push('/account/save'),
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
