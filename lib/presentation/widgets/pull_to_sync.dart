import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';

/// Pull down to sync, on any scrollable in the app.
class PullToSync extends ConsumerWidget {
  const PullToSync.group(String this.groupId, {super.key, required this.child});

  const PullToSync.everything({super.key, required this.child})
    : groupId = null;

  /// The group to sync, or null for every group this account belongs to.
  final String? groupId;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    onRefresh: () {
      final sync = ref.read(syncControllerProvider.notifier);
      final id = groupId;
      return id == null ? sync.syncAll() : sync.syncGroup(id);
    },
    child: child,
  );
}

/// Makes content that is shorter than the screen scroll anyway.
class FillsViewport extends StatelessWidget {
  const FillsViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );
}
