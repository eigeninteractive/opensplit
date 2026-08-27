import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import 'pull_to_sync.dart';
import '../../domain/balance/member_balance.dart';
import '../../domain/balance/simplify.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../format.dart';
import '../theme.dart';
import 'balance_arrow.dart';

/// Per-currency balances and, when the group wants them, the payments that
/// would settle it.
class BalancesPanel extends ConsumerWidget {
  const BalancesPanel({super.key, required this.ledger});

  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final scheme = Theme.of(context).colorScheme;

    if (ledger.isSettled && ledger.isCoherent) {
      return PullToSync.group(
        ledger.group.id,
        child: FillsViewport(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: scheme.primary,
                  ),
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
          ),
        ),
      );
    }

    return PullToSync.group(
      ledger.group.id,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // Above the numbers, because it is about whether to believe them.
          if (!ledger.isCoherent) _IncoherentLedgerCard(ledger: ledger),
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
            Card.outlined(
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
      ),
    );
  }
}

/// Says plainly that these numbers do not add up.
///
/// Reachable only if an entry on this device has payers or shares that disagree
/// with its own total, which nothing in the app can write — `composeEntry`
/// cannot build one and `writeEntryLocally` refuses to store one.
///
/// It exists because of what the alternative looked like. The settlement plan
/// is derived by matching debtors against creditors, so a journal that does not
/// sum to zero yields a short plan or none at all — and the group rendered
/// every member's position perfectly while simply offering no way to settle
/// them, with nothing on screen or in a release log to say why. A number that
/// is wrong is recoverable; a number that is wrong and says nothing is not.
class _IncoherentLedgerCard extends StatelessWidget {
  const _IncoherentLedgerCard({required this.ledger});

  final GroupLedger ledger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = ledger.brokenEntries.length;

    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 24),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'These balances do not add up',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$count ${count == 1 ? 'expense does' : 'expenses do'} not '
                    'match what was paid and what is owed, so the figures '
                    'below are incomplete and settling will not square the '
                    'group. Opening the expense and saving it again rebuilds '
                    'the split.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in ledger.brokenEntries.take(5))
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.centerLeft,
                        foregroundColor: scheme.onErrorContainer,
                      ),
                      onPressed: () =>
                          context.push('/g/${ledger.group.id}/e/${entry.id}'),
                      child: Text(
                        entry.description.isEmpty
                            ? 'Untitled expense'
                            : entry.description,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
        // "Indian Rupee · INR", not a Chip.
        //
        // This was a Chip with its padding zeroed and its density compacted,
        // which is two overrides to make a component stop looking like itself.
        // Chips are controls — they carry tap targets, selection and hover —
        // and this one was never tappable. A section heading that reads as a
        // button is a small lie; the code is just part of the name.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: currency?.name ?? code),
              if (currency?.name != null)
                TextSpan(
                  text: '  ·  $code',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card.outlined(
          child: Column(
            children: [
              for (final balance in balances)
                _MemberBalanceRow(
                  ledger: ledger,
                  balance: balance,
                  currency: currency,
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
          Card.outlined(
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

    final scheme = Theme.of(context).colorScheme;
    final words = isMine
        ? 'You pay $to'
        : '$from pays ${transfer.toMemberId == ledger.me?.id ? 'you' : to}';

    // One control in `trailing`, which is all a Material list item has room
    // for. This used to hold a help IconButton and the Settle button side by
    // side in a Wrap: two targets competing for a slot sized for one, which on
    // a narrow phone wrapped to a second line and dragged the row out of
    // alignment with every other row in the card.
    //
    // The explanation moves onto the row itself — tapping a list item to see
    // more about it is the ordinary gesture, and it gives the reasoning a far
    // bigger target than a 24dp icon. The icon stays as a hint that there is
    // something to tap, but it is no longer a separate button.
    return Semantics(
      // The tooltip that used to say this belonged to the help button, which
      // is gone; the row carries the affordance now, so it carries the words.
      hint: 'Shows how this payment was worked out',
      child: ListTile(
        onTap: () => _explain(context),
        title: Row(
          children: [
            Flexible(child: Text(words, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            ExcludeSemantics(
              child: Icon(
                Icons.help_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Text(
          formatMoney(currency, transfer.amountMinor),
          style: moneyStyle(Theme.of(context).textTheme.bodyMedium!),
        ),
        trailing: FilledButton.tonal(
          onPressed: () => context.push(
            '/g/${ledger.group.id}/settle'
            '?from=${transfer.fromMemberId}'
            '&to=${transfer.toMemberId}'
            '&amount=${transfer.amountMinor}'
            '&currency=${transfer.currency}',
          ),
          child: const Text('Settle'),
        ),
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

    // Lifted out of the widget tree rather than written inline. Down inside the
    // slivers there are twenty columns of indent before the quote even opens,
    // which leaves no room to say anything.
    final rest = transfer.amountMinor == net.abs()
        ? ''
        : ', plus the other suggested payments';
    final why =
        '${isMe ? 'You owe' : '$name owes'} '
        '${formatMoneyAbs(currency, net)} in total across this group. '
        'Rather than paying several people separately, that whole amount is '
        'cleared by paying ${ledger.nameOf(transfer.toMemberId)} '
        '${formatMoney(currency, transfer.amountMinor)}$rest.';
    const caveat =
        'This can name someone you never directly owed. It is the shortest '
        'set of payments that leaves everybody square.';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      // Slivers, because the contributing entries below are unbounded: every
      // expense the two of them share lands in that list, and a ListView would
      // build all of them before the sheet drew its first frame.
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverList.list(
                  children: [
                    Text(
                      'Why this payment?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(why, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      caveat,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      'Built from these entries',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (contributions.isEmpty)
                      const Text('No entries in this currency.'),
                  ],
                ),
                SliverList.builder(
                  itemCount: contributions.length,
                  itemBuilder: (context, index) {
                    final item = contributions[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.entry.description.isEmpty
                            ? (item.entry.kind == EntryKind.settlement
                                  ? 'Settlement'
                                  : 'Expense')
                            : item.entry.description,
                      ),
                      subtitle: Text(
                        DateFormat.yMMMd().format(item.entry.entryDate),
                      ),
                      trailing: BalanceAmount(
                        balanceMinor: item.delta,
                        text: formatMoneyAbs(currency, item.delta),
                        semanticsLabel: item.delta > 0
                            ? 'lent ${formatMoneyAbs(currency, item.delta)}'
                            : 'owed ${formatMoneyAbs(currency, item.delta)}',
                        style: moneyStyle(
                          Theme.of(context).textTheme.bodyMedium!,
                        ),
                      ),
                    );
                  },
                ),
                SliverList.list(
                  children: [
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Net',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        BalanceAmount(
                          balanceMinor: net,
                          text: formatMoneyAbs(currency, net),
                          semanticsLabel: net > 0
                              ? 'net, owed to you '
                                    '${formatMoneyAbs(currency, net)}'
                              : 'net, you owe ${formatMoneyAbs(currency, net)}',
                          style: moneyStyle(
                            Theme.of(context).textTheme.titleSmall!,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One member's standing in one currency.
///
/// Its own widget so that the wording, which needs three pieces of the same
/// balance, is assembled where there is room to read it rather than inside a
/// list comprehension nested four containers deep.
class _MemberBalanceRow extends StatelessWidget {
  const _MemberBalanceRow({
    required this.ledger,
    required this.balance,
    required this.currency,
  });

  final GroupLedger ledger;
  final MemberBalance balance;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    final amount = formatMoneyAbs(currency, balance.balanceMinor);
    final who = ledger.nameOf(balance.memberId);
    final verb = balance.balanceMinor > 0 ? 'is owed' : 'owes';
    final isMe = balance.memberId == ledger.me?.id;

    return ListTile(
      title: Text(isMe ? '$who (you)' : who),
      trailing: BalanceAmount(
        balanceMinor: balance.balanceMinor,
        text: '$verb $amount',
        semanticsLabel: '$who $verb $amount',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// One approximate figure for a group holding several currencies.
///
/// Renders nothing unless there is a real estimate to make. Everything about
/// it is hedged on purpose — the tilde, the word "roughly", and the named
/// currencies it could not convert — because this is the only number on the
/// screen that is not exact, and it sits directly above ones that are.
///
/// It is the sum of the per-expense figures, each converted at the rate stamped
/// on it. It deliberately does not answer "what would settling cost today":
/// that question is already answered exactly, per currency, by the rows below,
/// and answering it here too would put two numbers on one screen that cannot be
/// reconciled.
class _EstimateCard extends ConsumerWidget {
  const _EstimateCard({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estimate = ref.watch(groupEstimateProvider(groupId));
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    if (estimate == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final currency = currencies[estimate.currency];
    final owed = estimate.amountMinor > 0;
    final text = formatMoneyAbs(currency, estimate.amountMinor);

    final caveat = StringBuffer(
      'Each expense converted at its own rate on the day it happened, so this '
      'adds up to the figures below',
    );
    if (!estimate.isComplete) {
      // "except USD" would overstate it: the USD entries that do carry a rate
      // are still in the figure. Only the ones without are missing.
      caveat
        ..write(' — except expenses in ')
        ..write(estimate.unconverted.join(' and '))
        ..write(' that carry no rate, which are left out.');
    } else {
      caveat.write('.');
    }

    return Card.outlined(
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
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
