import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/balance_arrow.dart';
import '../widgets/balances_panel.dart';
import '../widgets/link_account_prompt.dart';
import '../widgets/page_body.dart';
import '../widgets/unsynced_changes_banner.dart';

/// Width at which the two halves of a group stop competing for the screen.
const double _wideBreakpoint = 840;

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final ledger = ref.watch(groupLedgerProvider(groupId));

    // Fire-and-forget: the screen is rendered from the local database, so this
    // only fills in what other devices have added. Its result is deliberately
    // not awaited or surfaced — there is no spinner to show.
    ref.watch(groupSyncProvider(groupId));

    if (groupAsync.hasValue && groupAsync.value == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('That group is not on this device.')),
      );
    }
    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }

    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, '/')),
        title: Text(ledger.group.name),
        actions: [
          IconButton(
            tooltip: 'People',
            onPressed: () => context.push('/g/$groupId/members'),
            icon: const Icon(Icons.people_outline),
          ),
          IconButton(
            tooltip: 'Insights',
            onPressed: () => context.push('/g/$groupId/insights'),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Settle up',
            onPressed: () => context.push('/g/$groupId/settle'),
            icon: const Icon(Icons.handshake_outlined),
          ),
        ],
        bottom: wide
            ? null
            : const TabBar(
                tabs: [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Balances'),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/g/$groupId/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      // Two panes are a master–detail layout and can take more width than a
      // single column, but not an unbounded amount: on a 27-inch monitor an
      // uncapped Row puts the expense list and the balances a foot apart.
      body: PageBody(
        maxWidth: wide ? 1200 : 760,
        child: Column(
          children: [
            // Above both panes rather than inside either: a write the server
            // refused makes the entry list and the balances beside it wrong
            // together, and it must be visible on whichever tab is open.
            const UnsyncedChangesBanner(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            ),
            // Also here, not only on the group list. Someone who arrived on an
            // invite link lands inside a group and stays there — they have the
            // most to lose, since the group is shared and their share of it is
            // real, and they are the least likely ever to see the list screen
            // the other copy of this sits on.
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: LinkAccountPrompt(),
            ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _EntriesList(ledger: ledger)),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 2, child: BalancesPanel(ledger: ledger)),
                      ],
                    )
                  : TabBarView(
                      children: [
                        _EntriesList(ledger: ledger),
                        BalancesPanel(ledger: ledger),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    // A TabBar needs a controller in scope, but only the narrow layout has
    // tabs at all; the wide one shows both panes at once.
    return wide ? scaffold : DefaultTabController(length: 2, child: scaffold);
  }
}

class _EntriesList extends ConsumerWidget {
  const _EntriesList({required this.ledger});

  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};

    if (ledger.entries.isEmpty) {
      return _EmptyEntries(groupId: ledger.group.id);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: ledger.entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = ledger.entries[index];
        return _EntryTile(
          entry: entry,
          ledger: ledger,
          currency: currencies[entry.currency],
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.ledger,
    required this.currency,
  });

  final Entry entry;
  final GroupLedger ledger;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = ledger.me;
    final isSettlement = entry.kind == EntryKind.settlement;

    // What this entry did to your position: what you paid, less what you owe.
    var myDelta = 0;
    if (me != null) {
      for (final payer in entry.payers) {
        if (payer.memberId == me.id) myDelta += payer.amountMinor;
      }
      for (final share in entry.shares) {
        if (share.memberId == me.id) myDelta -= share.amountMinor;
      }
    }

    final payerNames = entry.payers
        .map((p) => ledger.nameOf(p.memberId))
        .join(', ');

    final String subtitle;
    if (isSettlement) {
      final payee = entry.shares.isEmpty
          ? '—'
          : ledger.nameOf(entry.shares.first.memberId);
      subtitle = '$payerNames paid $payee';
    } else {
      subtitle =
          '$payerNames paid · ${DateFormat.MMMd().format(entry.entryDate)}';
    }

    return ListTile(
      onTap: () => context.push('/g/${ledger.group.id}/e/${entry.id}'),
      leading: CircleAvatar(
        backgroundColor: isSettlement
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          isSettlement ? Icons.handshake_outlined : Icons.receipt_outlined,
          size: 20,
          color: isSettlement
              ? scheme.onTertiaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        isSettlement && entry.description.isEmpty
            ? 'Settlement'
            : entry.description.isEmpty
            ? 'Expense'
            : entry.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(currency, entry.amountMinor),
            style: moneyStyle(Theme.of(context).textTheme.titleSmall!),
          ),
          if (me != null && myDelta != 0)
            BalanceAmount(
              balanceMinor: myDelta,
              text: myDelta > 0
                  ? 'you lent ${formatMoneyAbs(currency, myDelta)}'
                  : 'you owe ${formatMoneyAbs(currency, myDelta)}',
              semanticsLabel: myDelta > 0
                  ? 'you lent ${formatMoneyAbs(currency, myDelta)}'
                  : 'you owe ${formatMoneyAbs(currency, myDelta)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _EmptyEntries extends StatelessWidget {
  const _EmptyEntries({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_card_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Nothing yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add the first expense and balances appear straight away.',
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
