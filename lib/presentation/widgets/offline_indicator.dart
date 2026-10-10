import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/sync_providers.dart';

/// A cloud-off icon for the app bar while no server can be reached.
///
/// Tapping or hovering it says what that means. It goes away by itself once a
/// sync gets through, which the coordinator tries as soon as the network
/// returns.
class OfflineIndicator extends ConsumerWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    if (!status.enabled || !status.isOffline) return const SizedBox.shrink();
    return _OfflineIcon(changesWaiting: status.lastReport?.nextPushAt != null);
  }
}

class _OfflineIcon extends StatelessWidget {
  const _OfflineIcon({required this.changesWaiting});

  final bool changesWaiting;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: changesWaiting
        ? 'Offline. Your changes are saved on this device and will sync when '
              'you are back online.'
        : 'Offline. Showing what is saved on this device.',
    // A tap, not a long press, because there is nothing else a tap could do.
    triggerMode: TooltipTriggerMode.tap,
    child: Padding(
      // The 48dp an IconButton would occupy, so the actions stay aligned.
      padding: const EdgeInsets.all(12),
      child: Icon(
        Icons.cloud_off_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Previews the indicator without a backend.
@Preview(name: 'Offline', group: 'Sync', size: Size(360, 80))
Widget offlineIndicatorPreview() => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      title: const Text('Groups'),
      actions: const [_OfflineIcon(changesWaiting: true)],
    ),
  ),
);
