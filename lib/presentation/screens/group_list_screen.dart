import '../../application/backend_providers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/drift_group_repository.dart';
import '../launch_hold.dart';
import '../widgets/group_avatar_hero.dart';
import '../widgets/group_cover.dart';
import '../widgets/shared_element.dart';
import '../widgets/brand_mark.dart';
import '../widgets/conflicting_edit_banner.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_standing.dart';
import '../widgets/link_account_prompt.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/page_body.dart';
import '../widgets/pull_to_sync.dart';
import '../widgets/sync_refresh_button.dart';
import '../widgets/sync_status_notice.dart';
import '../widgets/unsynced_changes_banner.dart';

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = groupListingsProvider;

    final groupsAsync = ref.watch(source);
    final all = groupsAsync.value ?? const <GroupListing>[];
    final groups = [
      for (final listing in all)
        if (listing.isCurrent) listing.group,
    ];

    return DestinationScaffold(
      titleWidget: const BrandLockup(),
      actions: [
        const OfflineIndicator(),
        if (kIsWeb) const SyncRefreshButton.everything(),
      ],
      // The empty state is shown at once rather than held back until the
      // server confirms it, so an empty list says when it may yet fill.
      bottom: groups.isEmpty
          ? const InitialSyncProgress(label: 'Checking for your groups')
          : null,
      // Disabled until the device has learned what a currency is, which is only
      // ever true during a brand-new install's first sweep or on a rebuilt
      // device with no connection.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed:
            !ref.watch(requiresAppUpdateProvider) &&
                (ref.watch(referenceDataProvider).value ?? false)
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
        AsyncValue(hasValue: true) => _GroupList.slivers(groups: groups),
        // Nothing, rather than placeholder cards: at launch the splash covers
        // this, and afterwards a local read is too quick to be worth drawing.
        _ => const [LaunchPlaceholder(child: SliverToBoxAdapter())],
      },
    );
  }
}

/// The list itself, as slivers under the destination's app bar.
abstract final class _GroupList {
  static const _noticeGap = EdgeInsets.only(bottom: 8);

  static List<Widget> slivers({required List<Group> groups}) => [
    // The notices, each of which renders as nothing until it has something to
    // say.
    SliverPadding(
      padding: const EdgeInsets.only(top: 8),
      sliver: SliverList.list(
        children: [
          const UnsyncedChangesBanner(padding: _noticeGap),
          const ConflictingEditBanner(padding: _noticeGap),
          const LinkAccountPrompt(padding: _noticeGap),
          const SyncStatusBanner(padding: _noticeGap),
        ],
      ),
    ),
    if (groups.isEmpty)
      const SliverToBoxAdapter(child: _EmptyState())
    else
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        // Built lazily rather than assembled into a list, because every tile
        // subscribes to its own group's ledger: off-screen groups should not
        // be folding balances.
        sliver: SliverList.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == groups.length - 1 ? 0 : 12,
            ),
            child: _GroupTile(group: groups[index]),
          ),
        ),
      ),
    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
  ];
}

/// The way to the groups that are no longer in this list.
class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(group.id));
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final theme = Theme.of(context);
    const corners = BorderRadius.all(Radius.circular(20));

    // Stock cards and tiles retain Material's ink, focus and touch behaviour.
    return Card.filled(
      color: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: corners),
      child: Stack(
        children: [
          if (ledger != null)
            Positioned.fill(
              child: GroupCoverHero(
                ledger: ledger,
                borderRadius: corners,
                patternFade: 1,
              ),
            ),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              onTap: () => context.push('/g/${group.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              minLeadingWidth: 56,
              titleAlignment: ListTileTitleAlignment.top,
              leading: GroupAvatarHero(group: group, radius: 28),
              title: SharedText(
                tag: ('group-name', group.id),
                text: group.name,
                maxLines: null,
                style: theme.textTheme.titleLarge!.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: ledger == null
                  ? const LaunchPlaceholder(child: SizedBox(height: 20))
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ledger.me != null) ...[
                            Text(
                              '${ledger.members.length} '
                              '${ledger.members.length == 1 ? 'member' : 'members'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          GroupStanding(
                            ledger: ledger,
                            currencies: currencies,
                            style: theme.textTheme.bodyLarge,
                            overflow: TextOverflow.clip,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.groups_outlined,
    title: 'No groups yet',
    message: 'Create a group for a trip, flat or dinner.',
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
