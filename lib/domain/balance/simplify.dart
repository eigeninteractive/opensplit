import 'package:freezed_annotation/freezed_annotation.dart';

import 'member_balance.dart';

part 'simplify.freezed.dart';

/// A single suggested payment that moves a group toward settled.
@freezed
abstract class Transfer with _$Transfer {
  const factory Transfer({
    required String fromMemberId,
    required String toMemberId,
    required String currency,
    required int amountMinor,
  }) = _Transfer;
}

/// Reduces a set of balances to the fewest payments that settle them.
List<Transfer> simplifyDebts(Iterable<MemberBalance> balances) {
  final byCurrency = <String, List<MemberBalance>>{};
  for (final balance in balances) {
    if (balance.balanceMinor == 0) continue;
    byCurrency.putIfAbsent(balance.currency, () => []).add(balance);
  }

  final transfers = <Transfer>[];
  final currencies = byCurrency.keys.toList()..sort();

  for (final currency in currencies) {
    transfers.addAll(_simplifyOneCurrency(currency, byCurrency[currency]!));
  }
  return transfers;
}

List<Transfer> _simplifyOneCurrency(
  String currency,
  List<MemberBalance> balances,
) {
  // Mutable working copies; the inputs are immutable and stay that way.
  final credits = <String, int>{};
  final debits = <String, int>{};

  for (final balance in balances) {
    if (balance.balanceMinor > 0) {
      credits[balance.memberId] = balance.balanceMinor;
    } else if (balance.balanceMinor < 0) {
      debits[balance.memberId] = -balance.balanceMinor;
    }
  }

  final transfers = <Transfer>[];

  while (credits.isNotEmpty && debits.isNotEmpty) {
    final creditor = _largest(credits);
    final debtor = _largest(debits);

    final amount = credits[creditor]! < debits[debtor]!
        ? credits[creditor]!
        : debits[debtor]!;

    transfers.add(
      Transfer(
        fromMemberId: debtor,
        toMemberId: creditor,
        currency: currency,
        amountMinor: amount,
      ),
    );

    // At least one side reaches zero every iteration, so this terminates in at
    // most (creditors + debtors - 1) steps.
    credits[creditor] = credits[creditor]! - amount;
    debits[debtor] = debits[debtor]! - amount;
    if (credits[creditor] == 0) credits.remove(creditor);
    if (debits[debtor] == 0) debits.remove(debtor);
  }

  // Anything left means the balances did not sum to zero.
  return transfers;
}

/// The member with the largest amount, ties broken by ascending member id.
String _largest(Map<String, int> amounts) {
  String? best;
  var bestAmount = 0;
  for (final entry in amounts.entries) {
    if (best == null ||
        entry.value > bestAmount ||
        (entry.value == bestAmount && entry.key.compareTo(best) < 0)) {
      best = entry.key;
      bestAmount = entry.value;
    }
  }
  return best!;
}
