import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/push_providers.dart';
import '../../config.dart';
import 'inline_notice.dart';

/// Offers notifications when somebody first has a group shared with an account.
class NotificationInvitation extends ConsumerStatefulWidget {
  const NotificationInvitation({super.key});

  @override
  ConsumerState<NotificationInvitation> createState() =>
      _NotificationInvitationState();
}

class _NotificationInvitationState
    extends ConsumerState<NotificationInvitation> {
  bool _busy = false;

  Future<void> _choose(bool enable) async {
    setState(() => _busy = true);
    final controller = ref.read(notificationPreferenceProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!enable) {
        await controller.markDeclined();
      } else if (!await controller.enable() && messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Allow notifications for OpenSplit in your device or browser settings.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not enable notifications. Try again in Settings.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasPush || ref.watch(notificationPreferenceProvider) != null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InlineNotice(
        icon: Icons.notifications_outlined,
        title: 'Get group updates',
        message:
            'Get notified about expenses, payments and balances to settle.',
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _choose(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _choose(true),
            child: const Text('Enable notifications'),
          ),
        ],
      ),
    );
  }
}
