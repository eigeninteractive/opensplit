import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../data/web/boot_hint.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/group.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/balance_arrow.dart';
import '../widgets/create_group_sheet.dart';
import '../widgets/link_account_prompt.dart';
import '../widgets/unsynced_changes_banner.dart';

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider());

    // Leaves a note for the next cold start, so the web loader knows whether
    // to draw group cards or just the chrome. See [recordHasGroups] — it does
    // nothing on Android.
    if (groupsAsync.hasValue) {
      recordHasGroups(groupsAsync.value!.isNotEmpty);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenSplit'),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
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
          AsyncValue(hasValue: true, value: final groups?)
              when groups.isEmpty =>
            const _EmptyState(),
          AsyncValue(hasValue: true, value: final groups?) => _GroupList(
            groups: groups,
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
  const _GroupList({required this.groups});

  final List<Group> groups;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      // Two leading slots, each of which renders as nothing until it has
      // something to say. The refused-write banner comes first: it is the one
      // that means data is already wrong somewhere.
      itemCount: groups.length + 2,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => switch (index) {
        0 => const UnsyncedChangesBanner(),
        1 => const LinkAccountPrompt(),
        _ => _GroupTile(group: groups[index - 2]),
      },
    );
  }
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
            Icon(Icons.receipt_long_outlined, size: 56, color: scheme.primary),
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
