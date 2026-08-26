import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';

/// Pull down to sync, on any scrollable in the app.
///
/// Worth stating plainly, because "will this refresh the balances too?" is the
/// question a pull-to-refresh gesture always raises: there is nothing here that
/// refreshes only part of a screen. Every panel in this app — the expense list,
/// the balances beside it, the settle-up plan, the activity feed — is a query
/// over the local database, and none of them holds a cached copy of anything.
/// A sync writes to that database once and every open query re-emits.
///
/// So the only choice this makes is *how much* to fetch:
///
///  * [PullToSync.group] pushes the outbox and pulls one group — its members,
///    its profiles, its entries and its activity — in a single pass.
///  * [PullToSync.everything] does the same for every group the *server* says
///    this account belongs to, including ones this device has never seen. That
///    is the gesture that recovers a second device, so it belongs on the group
///    list rather than being reserved for a button in Settings.
///
/// Failures are deliberately silent. Being offline is the ordinary case for an
/// app that is meant to work without a server, and the screen is already
/// showing everything it knows.
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
///
/// A [RefreshIndicator] listens to a scrollable, and a scrollable with nothing
/// to scroll reports no overscroll — so the gesture quietly does not exist on
/// exactly the screens that most need it: an empty group, and a device that has
/// just signed in and has not pulled anything yet.
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
