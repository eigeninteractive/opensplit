import 'dart:collection';

import '../models/entry.dart';
import 'member_balance.dart';

/// Folds entries into per-member, per-currency balances.
///
/// This is the client-side twin of the `v_member_balances` view, and the single
/// source of display truth. Balances are derived on every read rather than
/// stored: a balances table has to be kept in step with every insert, edit,
/// soft delete and late-arriving sync, and the failure mode is a number that is
/// wrong with no way to tell that it is wrong.
///
/// Soft-deleted entries are skipped, exactly as the view's
/// `where deleted_at is null` does.
///
/// Members whose position nets to zero are omitted, matching the view's
/// `having sum(delta) <> 0`. An absent member is a settled member; callers
/// showing a roster should treat "not present" as zero rather than "unknown".
///
/// The result is ordered by currency then member id, so two devices holding the
/// same entries produce not just equal balances but an identical list.
List<MemberBalance> foldBalances(Iterable<Entry> entries) {
  // Keyed by currency, then member id.
  final totals = SplayTreeMap<String, SplayTreeMap<String, int>>();

  void add(String currency, String memberId, int delta) {
    final byMember = totals.putIfAbsent(currency, SplayTreeMap.new);
    byMember[memberId] = (byMember[memberId] ?? 0) + delta;
  }

  for (final entry in entries) {
    if (entry.isDeleted) continue;

    // Paying puts you in credit; owing a share puts you in debit. A settlement
    // folds through the identical path, which is precisely why it lives in the
    // same table: the payer's credit cancels the debt the expenses created.
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
///
/// Always empty for a journal this app wrote: `composeEntry` cannot build an
/// unbalanced entry and `writeEntryLocally` refuses to store one. It is checked
/// on the way out anyway because the consequence of being wrong is silent —
/// [foldBalances] over an unbalanced entry produces balances that do not sum to
/// zero, and a set of balances that does not sum to zero has no settlement plan
/// at all. The group would show everyone's position correctly and simply offer
/// no way to square it.
///
/// So this is the read-side twin of the write-side check: cheap, total, and it
/// names the entry rather than leaving a screen to guess why its numbers will
/// not reconcile.
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
