import 'dart:collection';

import '../models/entry.dart';
import 'member_balance.dart';

/// Folds entries into per-member, per-currency balances.
List<MemberBalance> foldBalances(Iterable<Entry> entries) {
  // Keyed by currency, then member id.
  final totals = SplayTreeMap<String, SplayTreeMap<String, int>>();

  void add(String currency, String memberId, int delta) {
    final byMember = totals.putIfAbsent(currency, SplayTreeMap.new);
    byMember[memberId] = (byMember[memberId] ?? 0) + delta;
  }

  for (final entry in entries) {
    if (entry.isDeleted) continue;

    // Paying puts you in credit; owing a share puts you in debit.
    for (final payer in entry.payers) {
      add(entry.currency, payer.memberId, payer.amountMinor);
    }
    for (final share in entry.shares) {
      add(entry.currency, share.memberId, -share.amountMinor);
    }
  }

  return [
    for (final currency in totals.entries)
      for (final member in currency.value.entries)
        if (member.value != 0)
          MemberBalance(
            memberId: member.key,
            currency: currency.key,
            balanceMinor: member.value,
          ),
  ];
}

/// The entries whose payers and shares do not agree with their own total.
List<Entry> unbalancedEntries(Iterable<Entry> entries) => [
  for (final entry in entries)
    if (!entry.isDeleted && !entry.isBalanced) entry,
];

/// Groups balances by currency, preserving the per-currency separation that
/// every downstream calculation depends on.
Map<String, List<MemberBalance>> balancesByCurrency(
  Iterable<MemberBalance> balances,
) {
  final result = SplayTreeMap<String, List<MemberBalance>>();
  for (final balance in balances) {
    result.putIfAbsent(balance.currency, () => []).add(balance);
  }
  for (final list in result.values) {
    list.sort((a, b) => a.memberId.compareTo(b.memberId));
  }
  return result;
}
