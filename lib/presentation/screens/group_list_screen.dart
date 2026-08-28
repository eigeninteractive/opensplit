import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/page_body.dart';
import '../widgets/pull_to_sync.dart';
import '../../application/providers.dart';
import '../../data/web/boot_hint.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/group.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/balance_arrow.dart';
import '../widgets/brand_mark.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/link_account_prompt.dart';
import '../widgets/conflicting_edit_banner.dart';
import '../widgets/unsynced_changes_banner.dart';
import '../widgets/sync_status_notice.dart';
import '../router.dart';

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Archived groups are pulled in here rather than queried separately, so
    // the list and the "archived" row at the bottom of it are two readings of
    // one stream and cannot disagree about which group is where.
    final source = groupsProvider(includeArchived: true);

    // Leaves a note for the next cold start, so the web loader knows whether to
    // draw group cards or just the chrome. See [recordHasGroups] — it does
    // nothing on Android.
    //
    // A listener rather than a line in the body, because it writes to browser
    // storage and a build has to be free of side effects. `ref.listen` fires on
    // change, which is every occasion that matters here: the provider is
    // created when this screen mounts and goes from loading to loaded while it
    // is watching.
    ref.listen(source, (_, next) {
      final loaded = next.value;
      if (loaded != null) {
        recordHasGroups(loaded.any((group) => !group.isArchived));
      }
    });

    final groupsAsync = ref.watch(source);
    final all = groupsAsync.value ?? const <Group>[];
    final groups = [
      for (final group in all)
        if (!group.isArchived) group,
    ];
    final archived = all.length - groups.length;

    return Scaffold(
      appBar: AppBar(title: const BrandLockup()),
      drawer: AdaptiveNavigation.drawerFor(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateGroupSheet(context),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
      body: PageBody(
        child: switch (groupsAsync) {
          AsyncError(:final error) => _Message(
            text: 'Could not load groups.\n$error',
          ),
          AsyncValue(hasValue: true) => _GroupList(
            groups: groups,
            archivedCount: archived,
          ),
          // The journal is local, so this window is a single frame rather
          // than anything the user perceives as loading.
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups, required this.archivedCount});

  final List<Group> groups;
  final int archivedCount;

  @override
  Widget build(BuildContext context) {
    // Four leading slots, each of which renders as nothing until it has
    // something to say. The refused-write banner comes first: it is the one
    // that means data is already wrong somewhere. The overtaken-edit banner
    // follows, because it means the group is right and this device's last
    // change to it was not.
    const leading = 4;
    final empty = groups.isEmpty;
    final rows = empty ? 1 : groups.length;
    final trailing = archivedCount > 0 ? 1 : 0;

    return PullToSync.everything(
      child: ListView.separated(
        // Always scrollable, so the gesture exists on a list too short to
        // scroll — which is exactly the list a new device shows.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: leading + rows + trailing,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        // Built lazily rather than assembled into a list, because every tile
        // subscribes to its own group's ledger: off-screen groups should not
        // be folding balances.
        itemBuilder: (context, index) {
          if (index == 0) return const UnsyncedChangesBanner();
          if (index == 1) return const ConflictingEditBanner();
          if (index == 2) return const LinkAccountPrompt();
          if (index == 3) {
            return empty ? const SizedBox.shrink() : const SyncStatusBanner();
          }

          final row = index - leading;
          if (empty) {
            return row == 0
                ? const InitialSyncGate(child: _EmptyState())
                : _ArchivedRow(count: archivedCount);
          }
          return row < groups.length
              ? _GroupTile(group: groups[row])
              : _ArchivedRow(count: archivedCount);
        },
      ),
    );
  }
}

/// The way to the groups that are no longer in this list.
///
/// At the bottom, and only when there is something behind it. An archived
/// group is by definition one nobody is thinking about, so it earns a row
/// rather than a permanent control in the app bar.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: ListTile(
      onTap: () => context.push('/archived'),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text('Archived groups ($count)'),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final scheme = Theme.of(context).colorScheme;

    return Card.outlined(
      child: InkWell(
        onTap: () => context.push('/g/${group.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.secondaryContainer,
                child: Icon(
                  group.isDirect ? Icons.person_outline : Icons.groups_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _Summary(
                      ledger: ledger,
                      currencies: currencies,
                      memberCount: ledger?.members.length,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one line that answers the only question anyone opens this app to ask.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.ledger,
    required this.currencies,
    required this.memberCount,
  });

  final GroupLedger? ledger;
  final Map<String, Currency> currencies;
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;

    if (ledger == null) return const SizedBox(height: 20);

    final me = ledger!.me;
    if (me == null) {
      return Text(
        '${memberCount ?? 0} ${memberCount == 1 ? 'member' : 'members'}',
        style: style?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    // One row per currency the group holds, because collapsing them would
    // require inventing an exchange rate the user never agreed to.
    final owed = <String>[];
    for (final code in ledger!.activeCurrencies) {
      final balance = ledger!.balanceOf(me.id, code);
      if (balance != 0) {
        owed.add(formatMoneyAbs(currencies[code], balance));
      }
    }

    if (owed.isEmpty) {
      return Text(
        'Settled up',
        style: style?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    // Direction is taken from the first non-zero currency; the group screen
    // breaks it down properly.
    final firstCode = ledger!.activeCurrencies.firstWhere(
      (code) => ledger!.balanceOf(me.id, code) != 0,
    );
    final net = ledger!.balanceOf(me.id, firstCode);

    final words = '${net > 0 ? 'You are owed' : 'You owe'} ${owed.join(' + ')}';
    return Semantics(
      label: words,
      child: ExcludeSemantics(
        child: Row(
          children: [
            BalanceArrow(balanceMinor: net, size: 15),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                words,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  color: balanceColor(scheme, net),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 56),
            const SizedBox(height: 20),
            Text(
              'No groups yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Make one for a trip, a flat, or a single dinner. '
              'You can add people who do not have the app.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(text)),
  );
}
