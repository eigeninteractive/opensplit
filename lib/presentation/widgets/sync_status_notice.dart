import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widget_previews.dart';

import '../../application/providers.dart';

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

/// Keeps saved data visible while explaining a failed refresh or upload.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final refreshFailed = status.error != null;
    if (!status.enabled ||
        (!refreshFailed && status.lastReport?.nextPushAt == null)) {
      return const SizedBox.shrink();
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(semanticsLabel: 'Checking for your groups'),
        SizedBox(height: 20),
        Text('Checking for your groups…', textAlign: TextAlign.center),
      ],
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
