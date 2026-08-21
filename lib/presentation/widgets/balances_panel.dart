import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/balance/simplify.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import 'balance_arrow.dart';
import '../format.dart';

/// Per-currency balances and, when the group wants them, the payments that
/// would settle it.
class BalancesPanel extends ConsumerWidget {
  const BalancesPanel({super.key, required this.ledger});

  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final scheme = Theme.of(context).colorScheme;

    if (ledger.isSettled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'All settled up',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Nobody owes anybody anything.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // The estimate leads, the exact per-currency figures follow directly
        // beneath it. That is the "breakdown one tap away" requirement met
        // without a tap: the authoritative numbers are never hidden behind the
        // approximate one.
        _EstimateCard(groupId: ledger.group.id),
        for (final code in ledger.activeCurrencies) ...[
          _CurrencySection(
            ledger: ledger,
            code: code,
            currency: currencies[code],
          ),
          const SizedBox(height: 24),
        ],
        if (ledger.activeCurrencies.length > 1)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This group holds more than one currency. Each is '
                      'settled on its own — cancelling one against another '
                      'would quietly hand the exchange-rate risk to whoever '
                      'the rounding favoured.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrencySection extends StatelessWidget {
  const _CurrencySection({
    required this.ledger,
    required this.code,
    required this.currency,
  });

  final GroupLedger ledger;
  final String code;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final balances = [
      for (final b in ledger.balances)
        if (b.currency == code) b,
    ]..sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));

    final transfers = [
      for (final t in ledger.transfers)
        if (t.currency == code) t,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              currency?.name ?? code,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(code),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final balance in balances)
                ListTile(
                  dense: true,
                  title: Text(
                    ledger.nameOf(balance.memberId) +
                        (balance.memberId == ledger.me?.id ? ' (you)' : ''),
                  ),
                  trailing: BalanceAmount(
                    balanceMinor: balance.balanceMinor,
                    text: balance.balanceMinor > 0
                        ? 'is owed ${formatMoneyAbs(currency, balance.balanceMinor)}'
                        : 'owes ${formatMoneyAbs(currency, balance.balanceMinor)}',
                    semanticsLabel:
                        '${ledger.nameOf(balance.memberId)} '
                        '${balance.balanceMinor > 0 ? 'is owed' : 'owes'} '
                        '${formatMoneyAbs(currency, balance.balanceMinor)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        if (transfers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Settle with ${transfers.length} '
                '${transfers.length == 1 ? 'payment' : 'payments'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final transfer in transfers)
                  _TransferTile(
                    ledger: ledger,
                    transfer: transfer,
                    currency: currency,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.ledger,
    required this.transfer,
    required this.currency,
  });

  final GroupLedger ledger;
  final Transfer transfer;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final isMine = transfer.fromMemberId == ledger.me?.id;
    final from = ledger.nameOf(transfer.fromMemberId);
    final to = ledger.nameOf(transfer.toMemberId);

    return ListTile(
      title: Text(
        isMine
            ? 'You pay $to'
            : '$from pays ${transfer.toMemberId == ledger.me?.id ? 'you' : to}',
      ),
      subtitle: Text(formatMoney(currency, transfer.amountMinor)),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Why this payment?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _explain(context),
          ),
          FilledButton.tonal(
            onPressed: () => context.go(
              '/g/${ledger.group.id}/settle'
              '?from=${transfer.fromMemberId}'
              '&to=${transfer.toMemberId}'
              '&amount=${transfer.amountMinor}'
              '&currency=${transfer.currency}',
            ),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }

  void _explain(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TransferExplanation(
        ledger: ledger,
        transfer: transfer,
        currency: currency,
      ),
    );
  }
}

/// Explains where a simplified payment came from.
///
/// Simplification can tell you to pay someone you never directly owed, because
/// it routes the shortest set of payments that clears everyone at once. Left
/// unexplained that is the single biggest complaint about apps that do this, so
/// the debt is always traceable back to the individual expenses that built it.
class _TransferExplanation extends StatelessWidget {
  const _TransferExplanation({
    required this.ledger,
    required this.transfer,
    required this.currency,
  });

  final GroupLedger ledger;
  final Transfer transfer;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final debtor = transfer.fromMemberId;
    final net = ledger.balanceOf(debtor, transfer.currency);

    // Every entry in this currency that moved the debtor's position, with the
    // amount it moved it by.
    final contributions = <({Entry entry, int delta})>[];
    for (final entry in ledger.entries) {
      if (entry.currency != transfer.currency) continue;
      var delta = 0;
      for (final payer in entry.payers) {
        if (payer.memberId == debtor) delta += payer.amountMinor;
      }
      for (final share in entry.shares) {
        if (share.memberId == debtor) delta -= share.amountMinor;
      }
      if (delta != 0) contributions.add((entry: entry, delta: delta));
    }

    final name = ledger.nameOf(debtor);
    final isMe = debtor == ledger.me?.id;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Why this payment?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            '${isMe ? 'You owe' : '$name owes'} '
            '${formatMoneyAbs(currency, net)} in total across this group. '
            'Rather than paying several people separately, that whole amount '
            'is cleared by paying ${ledger.nameOf(transfer.toMemberId)} '
            '${formatMoney(currency, transfer.amountMinor)}'
            '${transfer.amountMinor == net.abs() ? '' : ', plus the other suggested payments'}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This can name someone you never directly owed. It is the shortest '
            'set of payments that leaves everybody square.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Divider(height: 32),
          Text(
            'Built from these entries',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (contributions.isEmpty)
            const Text('No entries in this currency.')
          else
            for (final item in contributions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  item.entry.description.isEmpty
                      ? (item.entry.kind == EntryKind.settlement
                            ? 'Settlement'
                            : 'Expense')
                      : item.entry.description,
                ),
                subtitle: Text(DateFormat.yMMMd().format(item.entry.entryDate)),
                trailing: BalanceAmount(
                  balanceMinor: item.delta,
                  text: formatMoneyAbs(currency, item.delta),
                  semanticsLabel: item.delta > 0
                      ? 'lent ${formatMoneyAbs(currency, item.delta)}'
                      : 'owed ${formatMoneyAbs(currency, item.delta)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Net', style: Theme.of(context).textTheme.titleSmall),
              BalanceAmount(
                balanceMinor: net,
                text: formatMoneyAbs(currency, net),
                semanticsLabel: net > 0
                    ? 'net, owed to you ${formatMoneyAbs(currency, net)}'
                    : 'net, you owe ${formatMoneyAbs(currency, net)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One approximate figure for a group holding several currencies.
///
/// Renders nothing unless there is a real estimate to make. Everything about
/// it is hedged on purpose — the tilde, the word "roughly", the rate date, and
/// the named currencies it could not convert — because this is the only number
/// on the screen that is not exact, and it sits directly above ones that are.
class _EstimateCard extends ConsumerWidget {
  const _EstimateCard({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(groupEstimateProvider(groupId)).value;
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    if (estimate == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final currency = currencies[estimate.currency];
    final owed = estimate.amountMinor > 0;
    final text = formatMoneyAbs(currency, estimate.amountMinor);

    final caveat = StringBuffer('Converted at ECB rates from ')
      ..write(DateFormat.yMMMd().format(estimate.asOf));
    if (!estimate.isComplete) {
      caveat
        ..write('. ')
        ..write(estimate.unconverted.join(' and '))
        ..write(
          estimate.unconverted.length == 1
              ? ' is not covered and is left out.'
              : ' are not covered and are left out.',
        );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Roughly, across everything',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            BalanceAmount(
              balanceMinor: estimate.amountMinor,
              text: '≈ $text ${owed ? 'owed to you' : 'you owe'}',
              semanticsLabel:
                  'Estimated total: approximately $text '
                  '${owed ? 'owed to you' : 'that you owe'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              caveat.toString(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
