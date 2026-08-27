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
///
/// Runs each currency independently. Netting across currencies would let the
/// algorithm cancel a ₹500 debt against a €20 credit, which quietly hands the
/// exchange-rate risk to one member and produces a settlement neither party
/// agreed to. If a group holds three currencies, it gets three settlement
/// plans.
///
/// Within a currency the rule is greedy: repeatedly send money from the largest
/// debtor to the largest creditor. This clears at least one member per step, so
/// a group of n members settles in at most n-1 payments instead of the up-to
/// n(n-1)/2 that paying every individual debt would take.
///
/// Ties are broken by ascending member id at both ends, making the plan
/// deterministic — the same balances always yield the same instructions, so two
/// people looking at the same group are not told to pay different friends.
///
/// This is a derived view and never writes rows. The underlying debts stay
/// intact underneath, which is what allows "you owe Arun ₹340" to be drilled
/// back to the expenses that produced it. Unexplainable simplified debts are
/// the single most common complaint about apps that do this.
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

  // Anything left means the balances did not sum to zero. That cannot happen
  // for a sound journal — every entry contributes its amount once as credit and
  // once as debit — so reaching here means the entries this was folded from are
  // themselves inconsistent.
  //
  // This used to be an `assert`, which is exactly the wrong instrument. Asserts
  // are stripped from a release build, so the one build where nobody is
  // watching a console was the one that said nothing: a one-sided set of
  // balances left this loop immediately, and the group's settlement plan simply
  // did not render. Correct-looking totals with no way to settle them, and no
  // error anywhere.
  //
  // A pure function is also the wrong place to decide what the user is told.
  // So this stays total and returns the payments it could match, and detecting
  // the condition belongs to whoever is about to put it on a screen — see
  // [unbalancedEntries], which finds the actual culprit rather than inferring
  // it from a residue.
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
