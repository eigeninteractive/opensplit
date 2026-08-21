import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/balance/simplify.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../format.dart';
import '../theme.dart';

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
    final scheme = Theme.of(context).colorScheme;
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
                  trailing: Text(
                    balance.balanceMinor > 0
                        ? 'is owed ${formatMoneyAbs(currency, balance.balanceMinor)}'
                        : 'owes ${formatMoneyAbs(currency, balance.balanceMinor)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: balanceColor(scheme, balance.balanceMinor),
                      fontWeight: FontWeight.w600,
                    ),
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
                trailing: Text(
                  formatMoney(currency, item.delta, alwaysSigned: true),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: balanceColor(scheme, item.delta),
                  ),
                ),
              ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Net', style: Theme.of(context).textTheme.titleSmall),
              Text(
                formatMoney(currency, net, alwaysSigned: true),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: balanceColor(scheme, net),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
