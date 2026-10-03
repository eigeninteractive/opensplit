import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/drift_group_repository.dart';
import '../../data/web/boot_hint.dart';
import '../widgets/avatar_view.dart';
import '../widgets/brand_mark.dart';
import '../widgets/conflicting_edit_banner.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_skeleton.dart';
import '../widgets/group_standing.dart';
import '../widgets/link_account_prompt.dart';
import '../widgets/page_body.dart';
import '../widgets/pull_to_sync.dart';
import '../widgets/segmented_list.dart';
import '../widgets/sync_refresh_button.dart';
import '../widgets/sync_status_notice.dart';
import '../widgets/unsynced_changes_banner.dart';

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Archived and left groups are pulled in here rather than queried
    // separately, so the list and the "archived" row at the bottom of it are
    // two readings of one stream and cannot disagree about which group is
    // where.
    final source = groupListingsProvider;

    // Leaves a note for the next cold start, so the web loader knows whether to
    // draw group cards or just the chrome.
    ref.listen(source, (_, next) {
      final loaded = next.value;
      if (loaded != null) {
        recordHasGroups(loaded.any((listing) => listing.isCurrent));
      }
    });

    final groupsAsync = ref.watch(source);
    final all = groupsAsync.value ?? const <GroupListing>[];
    final groups = [
      for (final listing in all)
        if (listing.isCurrent) listing.group,
    ];
    final archived = all.length - groups.length;

    return DestinationScaffold(
      titleWidget: const BrandLockup(),
      actions: [if (kIsWeb) const SyncRefreshButton.everything()],
      // Disabled until the device has learned what a currency is, which is only
      // ever true during a brand-new install's first sweep or on a rebuilt
      // device with no connection.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ref.watch(referenceDataProvider).value ?? false
            ? () => showCreateGroupSheet(context)
            : null,
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
      // PullToSync wraps the scroll view rather than living inside it, so it
      // goes around the whole destination -- which is why this one screen
      // builds its own rather than handing slivers over.
      wrap: (view) => PullToSync.everything(child: view),
      slivers: switch (groupsAsync) {
        AsyncError(:final error) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(text: 'Could not load groups.\n$error'),
          ),
        ],
        AsyncValue(hasValue: true) => _GroupList.slivers(
          groups: groups,
          archivedCount: archived,
        ),
        _ => const [GroupListSkeleton()],
      },
    );
  }
}

/// The list itself, as slivers under the destination's app bar.
abstract final class _GroupList {
  static const _noticeGap = EdgeInsets.only(bottom: 8);

  static List<Widget> slivers({
    required List<Group> groups,
    required int archivedCount,
  }) => [
    // The notices, each of which renders as nothing until it has something to
    // say.
    SliverPadding(
      padding: const EdgeInsets.only(top: 8),
      sliver: SliverList.list(
        children: [
          const UnsyncedChangesBanner(padding: _noticeGap),
          const ConflictingEditBanner(padding: _noticeGap),
          const LinkAccountPrompt(padding: _noticeGap),
          if (groups.isNotEmpty) const SyncStatusBanner(padding: _noticeGap),
        ],
      ),
    ),
    if (groups.isEmpty)
      const SliverToBoxAdapter(child: InitialSyncGate(child: _EmptyState()))
    else
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        // Built lazily rather than assembled into a list, because every tile
        // subscribes to its own group's ledger: off-screen groups should not
        // be folding balances.
        sliver: SliverList.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) => Segment(
            index: index,
            count: groups.length,
            child: _GroupTile(group: groups[index]),
          ),
        ),
      ),
    if (archivedCount > 0)
      SliverToBoxAdapter(child: _ArchivedRow(count: archivedCount)),
    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
  ];
}

/// The way to the groups that are no longer in this list.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    // A group of one, apart from the groups above it.
    child: SegmentedList(
      children: [
        ListTile(
          onTap: () => context.push('/archived'),
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text('Archived groups ($count)'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(group.id));
    final currencies = ref.watch(currenciesProvider).value ?? const {};

    // A real ListTile, for its touch target, density and large-font growth.
    return ListTile(
      onTap: () => context.push('/g/${group.id}'),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 24, 8),
      leading: AvatarView(
        avatar: group.avatar,
        name: group.name,
        id: group.id,
        radius: 24,
      ),
      title: Text(group.name, overflow: TextOverflow.ellipsis),
      titleTextStyle: Theme.of(context).textTheme.titleMedium,
      subtitle: ledger == null
          ? const SizedBox(height: 20)
          : GroupStanding(ledger: ledger, currencies: currencies),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.groups_outlined,
    title: 'No groups yet',
    message:
        'Make one for a trip, a flat, or a single dinner. '
        'You can add people who do not have the app.',
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
  );
}
