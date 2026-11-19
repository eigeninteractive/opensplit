import '../../application/backend_providers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/ledger_providers.dart';
import '../../application/preferences_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../data/repositories/drift_group_repository.dart';
import '../launch_hold.dart';
import '../widgets/group_avatar_hero.dart';
import '../widgets/group_cover.dart';
import '../widgets/shared_element.dart';
import '../widgets/segmented_list.dart';
import '../widgets/brand_mark.dart';
import '../widgets/conflicting_edit_banner.dart';
import '../widgets/create_group_sheet.dart';
import '../../domain/money_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/folded_section.dart';
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
        if (listing.isCurrent) listing,
    ];
    final overview = ref.watch(groupsOverviewProvider);
    final currencies = ref.watch(currenciesProvider).value ?? const {};

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
        AsyncValue(hasValue: true) => _GroupList.slivers(
          groups: [
            for (final listing in groups)
              if (!overview.quietGroupIds.contains(listing.group.id)) listing,
          ],
          settled: [
            for (final listing in groups)
              if (overview.quietGroupIds.contains(listing.group.id)) listing,
          ],
          standing: overview.standing,
          currencies: currencies,
        ),
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

  /// [settled] are the groups with nothing owed and nothing happening,
  /// folded away under the ones still in use.
  static List<Widget> slivers({
    required List<GroupListing> groups,
    required List<GroupListing> settled,
    required OverallStanding standing,
    required Map<String, Currency> currencies,
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
          const SyncStatusBanner(padding: _noticeGap),
        ],
      ),
    ),
    // One group's figure is already the whole story.
    if (standing.groupsWithBalance > 1)
      SliverToBoxAdapter(
        child: _Overall(standing: standing, currencies: currencies),
      ),
    if (groups.isEmpty && settled.isEmpty)
      const SliverToBoxAdapter(child: _EmptyState())
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
            child: _GroupTile(
              listing: groups[index],
              corners: Segment.radiusAt(index: index, count: groups.length),
            ),
          ),
        ),
      ),
    if (settled.isNotEmpty)
      SliverPadding(
        padding: const EdgeInsets.only(top: 16),
        sliver: SliverToBoxAdapter(
          child: FoldedSection(
            storageKey: 'settled-groups',
            title: 'Settled groups',
            summary:
                '${settled.length} '
                '${settled.length == 1 ? 'group' : 'groups'} with nothing owed '
                'and no recent activity',
            initiallyExpanded: groups.isEmpty,
            children: [
              for (final listing in settled)
                _GroupTile(listing: listing, corners: BorderRadius.zero),
            ],
          ),
        ),
      ),
    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
  ];
}

/// Where you stand across every group, above the groups themselves.
class _Overall extends StatelessWidget {
  const _Overall({required this.standing, required this.currencies});

  final OverallStanding standing;
  final Map<String, Currency> currencies;

  List<String> _figures(Map<String, int> amounts) => [
    for (final code in amounts.keys.toList()..sort())
      formatMoneyAbs(currencies[code], amounts[code]!),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Across ${standing.groupsWithBalance} groups',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          StandingLines(
            owed: _figures(standing.owed),
            owing: _figures(standing.owing),
            style: theme.textTheme.titleMedium!,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }
}

/// A group's identity and balances, opening its expenses and people.
class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.listing, required this.corners});

  final GroupListing listing;
  final BorderRadius corners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = listing.group;
    final ledger = ref.watch(groupLedgerProvider(group.id));
    // Something happened here since this device last had the group open.
    final hasNews = switch (ref.watch(groupSeenAtProvider(group.id))) {
      final seen? => listing.lastActivityAt.isAfter(seen),
      null => false,
    };
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final theme = Theme.of(context);
    // The segment owns containment; the tile keeps Material's ink and focus.
    return Stack(
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
            leading: Badge(
              isLabelVisible: hasNews,
              smallSize: 12,
              child: GroupAvatarHero(group: group, radius: 28),
            ),
            title: Semantics(
              hint: hasNews ? 'New activity' : null,
              child: SharedText(
                tag: ('group-name', group.id),
                placeholderBuilder: settledRouteHeroPlaceholder,
                text: group.name,
                maxLines: null,
                style: theme.textTheme.titleLarge!.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
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
