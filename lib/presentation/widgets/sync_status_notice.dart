import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync_providers.dart';
import '../launch_hold.dart';

/// Stands in, invisibly, for saved content the local database has not
/// returned yet.
///
/// At launch the splash covers it (see [LaunchHold]); after launch a local
/// read finishes before a spinner would be worth drawing.
class SavedDataLoading extends StatelessWidget {
  const SavedDataLoading({super.key, required this.label});

  /// The saved content being opened, for screen readers.
  final String label;

  @override
  Widget build(BuildContext context) => LaunchPlaceholder(
    child: Semantics(label: label, child: const SizedBox.expand()),
  );
}

/// Distinguishes an empty local cache from a verified empty server result.
class InitialSyncGate extends ConsumerWidget {
  const InitialSyncGate({super.key, required this.child});

  /// The empty state to display after a successful refresh.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    if (!status.enabled) return child;
    if (status.isSyncing ||
        (!status.hasCompletedFullSync && status.error == null)) {
      return const _CheckingGroups();
    }
    if (status.error != null) {
      return _SyncProblem(
        title: 'Could not refresh your groups',
        message:
            'Check your connection and try again. '
            'You can still create a group offline.',
        onRetry: () => ref.read(syncControllerProvider.notifier).syncAll(),
      );
    }
    return child;
  }
}

/// A thin bar under the app bar while this session's first full refresh runs.
///
/// Saved data is shown as soon as the device has read it; this only says that
/// more may still arrive from the server. Later refreshes stay quiet, so a
/// write or a return to the foreground does not flash it. The bar's height is
/// reserved even while idle, so content does not shift when it disappears.
class InitialSyncProgress extends ConsumerWidget
    implements PreferredSizeWidget {
  const InitialSyncProgress({super.key, required this.label});

  /// What is being checked, for screen readers.
  final String label;

  @override
  Size get preferredSize => const Size.fromHeight(4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final checking =
        status.enabled && status.isSyncing && !status.hasCompletedFullSync;
    return SizedBox.fromSize(
      size: preferredSize,
      child: checking ? LinearProgressIndicator(semanticsLabel: label) : null,
    );
  }
}

/// Keeps saved data visible while explaining a failed refresh or upload.
///
/// Says nothing while offline: for an app that works offline that is a normal
/// state, not a problem to act on, and [OfflineIndicator] in the app bar
/// already says it.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final refreshFailed = status.error != null;
    final changesWaiting = status.lastReport?.nextPushAt != null;
    if (!status.enabled || (!refreshFailed && !changesWaiting)) {
      return const SizedBox.shrink();
    }
    if (status.isOffline) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: _SyncProblem(
        title: refreshFailed ? 'Could not refresh' : 'Changes waiting to sync',
        message: refreshFailed
            ? 'Showing saved data. We will retry automatically.'
            : 'Your changes are saved on this device. '
                  'We will retry sending them automatically.',
        onRetry: status.isSyncing
            ? null
            : () => ref.read(syncControllerProvider.notifier).syncAll(),
      ),
    );
  }
}

class _CheckingGroups extends StatelessWidget {
  const _CheckingGroups();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(
        semanticsLabel: 'Checking for your groups',
      ),
    ),
  );
}

class _SyncProblem extends StatelessWidget {
  const _SyncProblem({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(onRetry == null ? 'Retrying…' : 'Try again'),
          ),
        ],
      ),
    ),
  );
}

/// Previews the failure notice without a backend or local database.
@Preview(name: 'Sync failure', group: 'Sync', size: Size(360, 220))
Widget syncFailurePreview() => MaterialApp(
  home: Scaffold(
    body: _SyncProblem(
      title: 'Could not refresh',
      message: 'Showing saved data. We will retry automatically.',
      onRetry: () {},
    ),
  ),
);
