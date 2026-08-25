import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../data/sync/outbox_queue.dart';

/// Says out loud that something recorded on this device never reached anyone.
///
/// The outbox sets aside a write the server refuses in a way retrying cannot
/// fix, so that one poisoned item cannot wedge everything queued behind it.
/// That is right, but on its own it produces the worst failure this app has:
/// not a crash, but an expense that looks saved forever on one phone and does
/// not exist for anybody else — discovered weeks later as two people reading
/// different balances, with nothing anywhere to explain it.
///
/// So it is stated plainly and it does not go away on its own. Offline is
/// silent, because offline is normal and resolves itself; this is neither.
class UnsyncedChangesBanner extends ConsumerWidget {
  const UnsyncedChangesBanner({super.key, this.padding = EdgeInsets.zero});

  /// Applied only when there is something to show, so that an empty banner
  /// does not leave a gap where a caller placed it in a column.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failures = ref.watch(failedWritesProvider).value ?? const [];
    if (failures.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = failures.length;

    return Padding(
      padding: padding,
      // MaterialBanner, rather than the Card and Row this used to build by
      // hand. Material's definition of a banner is "an important, succinct
      // message with actions, that requires a user action to dismiss" — which
      // is this, exactly. Using the component means the leading icon, the
      // content style, the action layout and the divider all come from the
      // theme instead of being re-specified here.
      child: MaterialBanner(
        backgroundColor: scheme.errorContainer,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onErrorContainer,
        ),
        leading: Icon(
          Icons.sync_problem_rounded,
          color: scheme.onErrorContainer,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count == 1
                  ? 'One change could not be saved'
                  : '$count changes could not be saved',
              style: text.titleSmall?.copyWith(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 4),
            Text(
              count == 1
                  ? '“${failures.single.label}” is on this device only. Nobody '
                        'else in the group can see it, and it is not counted '
                        'in their balances.'
                  : 'They are on this device only. Nobody else in the group '
                        'can see them, and they are not counted in their '
                        'balances.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _showDetails(context, failures),
            child: const Text('Details'),
          ),
          FilledButton(
            onPressed: () =>
                ref.read(syncControllerProvider.notifier).retryFailed(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  /// The server's own words, unedited.
  ///
  /// Almost nobody will read this. The one person who does is trying to work
  /// out why their balance is wrong, and a paraphrase would cost them the only
  /// evidence there is.
  void _showDetails(BuildContext context, List<FailedWrite> failures) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not saved to the server'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final failure in failures)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failure.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        failure.reason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
