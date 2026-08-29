import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync_providers.dart';

/// Refreshes through the same coordinator as pull-to-refresh and automatic sync.
///
/// Progress reflects account-wide synchronization, not just this button's last
/// click. Local query providers stay mounted so saved data remains visible.
class SyncRefreshButton extends ConsumerWidget {
  /// Refreshes all groups, including ones not yet saved on this device.
  const SyncRefreshButton.everything({super.key}) : groupId = null;

  /// Refreshes one group's ledger.
  const SyncRefreshButton.group(String this.groupId, {super.key});

  /// The group to refresh, or `null` for the whole account.
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    if (!status.enabled) return const SizedBox.shrink();
    return _RefreshIconButton(
      isSyncing: status.isSyncing,
      onRefresh: () async {
        final sync = ref.read(syncControllerProvider.notifier);
        final id = groupId;
        await (id == null ? sync.syncAll() : sync.syncGroup(id));
      },
    );
  }
}

class _RefreshIconButton extends StatelessWidget {
  const _RefreshIconButton({required this.isSyncing, required this.onRefresh});

  final bool isSyncing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: isSyncing ? 'Syncing…' : 'Refresh',
    onPressed: isSyncing ? null : onRefresh,
    icon: isSyncing
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
              semanticsLabel: 'Syncing saved data',
            ),
          )
        : const Icon(Icons.refresh),
  );
}

/// Previews idle and busy refresh controls without a backend.
@Preview(name: 'Refresh states', group: 'Sync', size: Size(320, 100))
Widget syncRefreshPreview() => MaterialApp(
  home: Scaffold(
    body: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RefreshIconButton(isSyncing: false, onRefresh: () {}),
        _RefreshIconButton(isSyncing: true, onRefresh: () {}),
      ],
    ),
  ),
);
