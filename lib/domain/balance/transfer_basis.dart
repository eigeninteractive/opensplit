import '../models/entry.dart';
import 'pairwise.dart';
import 'simplify.dart';

/// One expense behind a suggested payment, and how far it moved what that
/// payment settles: positive when it put the payer in credit.
typedef Contribution = ({Entry entry, int delta});

/// The expenses behind [transfer], and the figure they come to.
///
/// When the group simplifies its debts, a payment settles the payer's whole
/// position, so every expense in its currency that moved the payer counts.
/// Otherwise it settles one pair's debt, and only what passed between those
/// two counts. Either way [net] is the sum of the contributions, from the
/// payer's side, so a person can check the one against the other.
({List<Contribution> contributions, int net}) basisOf(
  Transfer transfer,
  Iterable<Entry> entries, {
  required bool simplified,
}) {
  final contributions = <Contribution>[
    for (final entry in entries)
      if (!entry.isDeleted && entry.row.currency == transfer.currency)
        (
          entry: entry,
          delta: simplified
              ? _positionMovedBy(entry, transfer.fromMemberId)
              : -pairDebtWithin(
                  entry,
                  debtor: transfer.fromMemberId,
                  creditor: transfer.toMemberId,
                ),
        ),
  ]..removeWhere((contribution) => contribution.delta == 0);

  return (
    contributions: contributions,
    net: contributions.fold(0, (sum, item) => sum + item.delta),
  );
}

/// What [memberId] paid towards [entry], less their share of it.
int _positionMovedBy(Entry entry, String memberId) {
  var delta = 0;
  for (final payer in entry.payers) {
    if (payer.memberId == memberId) delta += payer.amountMinor;
  }
  for (final share in entry.shares) {
    if (share.memberId == memberId) delta -= share.amountMinor;
  }
  return delta;
}
