import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync_providers.dart';
import '../launch_hold.dart';

/// Indicates that the local database has not produced its first result yet.
class SavedDataLoading extends StatelessWidget {
  const SavedDataLoading({super.key, required this.label});

  /// The saved content being opened, distinct from a network refresh.
  final String label;

  @override
  Widget build(BuildContext context) => LaunchPlaceholder(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: CircularProgressIndicator(semanticsLabel: label),
      ),
    ),
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
/// Being offline gets a single quiet line rather than a card: for an app that
/// works offline it is a normal state, not a problem to act on, and it fixes
/// itself when the network comes back.
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
    if (status.isOffline) {
      return Padding(
        padding: padding,
        child: _OfflineNote(changesWaiting: changesWaiting),
      );
    }
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

class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.changesWaiting});

  final bool changesWaiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                changesWaiting
                    ? 'Offline. Your changes will sync when you are back '
                          'online.'
                    : 'Offline. Showing what is saved on this device.',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// Previews the quiet line shown while the device is offline.
@Preview(name: 'Offline', group: 'Sync', size: Size(360, 80))
Widget offlinePreview() =>
    const MaterialApp(home: Scaffold(body: _OfflineNote(changesWaiting: true)));

/// Previews the local database loading state before any saved rows are ready.
@Preview(name: 'Opening saved groups', group: 'Sync', size: Size(360, 240))
Widget savedDataLoadingPreview() => const MaterialApp(
  home: Scaffold(body: SavedDataLoading(label: 'Loading saved groups')),
);
