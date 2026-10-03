import '../models/entry.dart';
import '../split/allocation.dart';
import 'simplify.dart';

/// What one expense leaves each person owing each payer, keyed by
/// `(debtor, creditor)`.
///
/// Every share is owed to the payers in proportion to what each of them paid.
/// Shares are taken one at a time, in member order, each divided by the same
/// largest-remainder rule the split uses against what every payer is still
/// owed. So it all comes out in whole minor units, each share is owed in full,
/// and each payer is paid back exactly what they paid, with no unit lost to
/// rounding. Nobody owes themselves. A deleted expense owes nothing, and nor
/// does one that does not add up, which the group screen flags instead.
Map<(String, String), int> debtsWithin(Entry entry) {
  final debts = <(String, String), int>{};
  if (entry.isDeleted || !entry.isBalanced) return debts;

  final outstanding = {
    for (final payer in entry.payers) payer.memberId: payer.amountMinor,
  };
  final shares = [...entry.shares]
    ..sort((a, b) => a.memberId.compareTo(b.memberId));

  for (final share in shares) {
    if (share.amountMinor == 0) continue;
    final owed = allocateLargestRemainder(
      totalMinor: share.amountMinor,
      parties: [
        for (final MapEntry(key: payer, value: left) in outstanding.entries)
          (memberId: payer, weightMicros: left),
      ],
      seed: '${entry.id}:${share.memberId}',
    );
    for (final MapEntry(key: payer, value: amount) in owed.entries) {
      outstanding[payer] = outstanding[payer]! - amount;
      if (payer == share.memberId || amount == 0) continue;
      final pair = (share.memberId, payer);
      debts[pair] = (debts[pair] ?? 0) + amount;
    }
  }
  return debts;
}

/// What [debtor] owes [creditor] on account of [entry], less what [creditor]
/// owes [debtor] on it. Negative when the expense ran the other way.
int pairDebtWithin(
  Entry entry, {
  required String debtor,
  required String creditor,
}) {
  final debts = debtsWithin(entry);
  return (debts[(debtor, creditor)] ?? 0) - (debts[(creditor, debtor)] ?? 0);
}

/// Who owes whom, pair by pair, when a group does not simplify its debts.
///
/// The debts of every expense between each two people are netted against
/// each other, per currency, and nothing more: a payment is only ever
/// suggested between two people who actually shared an expense. Settling
/// every one of them leaves everybody square, exactly as the fewest payments
/// from [simplifyDebts] would, in more steps.
List<Transfer> pairwiseDebts(Iterable<Entry> entries) {
  final net = <(String, String, String), int>{};
  for (final entry in entries) {
    for (final MapEntry(key: (debtor, creditor), value: amount) in debtsWithin(
      entry,
    ).entries) {
      // One key per unordered pair, signed: positive when the first named
      // owes the second.
      final forward = debtor.compareTo(creditor) < 0;
      final key = forward
          ? (entry.row.currency, debtor, creditor)
          : (entry.row.currency, creditor, debtor);
      net[key] = (net[key] ?? 0) + (forward ? amount : -amount);
    }
  }

  final transfers = [
    for (final MapEntry(key: (currency, first, second), value: amount)
        in net.entries)
      if (amount != 0)
        Transfer(
          fromMemberId: amount > 0 ? first : second,
          toMemberId: amount > 0 ? second : first,
          currency: currency,
          amountMinor: amount.abs(),
        ),
  ];
  return transfers..sort(
    (a, b) => [
      a.currency.compareTo(b.currency),
      a.fromMemberId.compareTo(b.fromMemberId),
      a.toMemberId.compareTo(b.toMemberId),
    ].firstWhere((order) => order != 0, orElse: () => 0),
  );
}
