import 'dart:collection';

import '../models/currency.dart';
import '../models/entry.dart';
import 'convert.dart';

/// A single figure standing in for money held in several currencies.
class EstimatedTotal {
  const EstimatedTotal({
    required this.amountMinor,
    required this.currency,
    required this.unconverted,
  });

  /// The converted sum, in [currency]'s minor units.
  final int amountMinor;

  /// The currency everything was converted into — the group's default.
  final String currency;

  /// Currencies in which at least one entry carries no rate.
  final List<String> unconverted;

  bool get isComplete => unconverted.isEmpty;
}

/// Folds one member's position into a single estimated figure, converting each
/// entry at the rate stored on that entry.
EstimatedTotal? estimateBalance({
  required Iterable<Entry> entries,
  required String memberId,
  required String target,
  required Map<String, Currency> currencies,
}) {
  final targetCurrency = currencies[target];
  if (targetCurrency == null) return null;

  var total = 0;
  var convertedAny = false;
  final unconverted = SplayTreeSet<String>();

  for (final entry in entries) {
    if (entry.isDeleted) continue;

    // The same arithmetic the balance fold does, kept per entry so each one can
    // be converted at its own rate: paying puts you in credit, owing a share
    // puts you in debit.
    var delta = 0;
    for (final payer in entry.payers) {
      if (payer.memberId == memberId) delta += payer.amountMinor;
    }
    for (final share in entry.shares) {
      if (share.memberId == memberId) delta -= share.amountMinor;
    }
    if (delta == 0) continue;

    if (entry.currency == target) {
      total += delta;
      convertedAny = true;
      continue;
    }

    final from = currencies[entry.currency];
    final rate = entry.fxRate;
    if (from == null || rate == null || rate <= 0) {
      unconverted.add(entry.currency);
      continue;
    }

    total += convertMinor(
      amountMinor: delta,
      from: from,
      to: targetCurrency,
      rate: rate,
    );
    convertedAny = true;
  }

  // Nothing was converted, so there is no estimate to make — as distinct from
  // an estimate of zero, which is a real and different answer.
  if (!convertedAny) return null;

  return EstimatedTotal(
    amountMinor: total,
    currency: target,
    unconverted: unconverted.toList(),
  );
}
