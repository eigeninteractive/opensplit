import 'dart:collection';

import '../models/currency.dart';
import '../models/entry.dart';
import 'convert.dart';

/// A single figure standing in for money held in several currencies.
///
/// Always an estimate, and shaped so a caller cannot forget that: it names the
/// currencies it could not convert at all rather than quietly under-reporting.
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
  ///
  /// Not the whole currency: entries in it that do carry a rate are still in
  /// the figure, and only the ones without are missing. Most often a backdated
  /// entry predating the rates we hold, or one recorded with no connection.
  /// The figure stays honest by naming what it left out.
  final List<String> unconverted;

  bool get isComplete => unconverted.isEmpty;
}

/// Folds one member's position into a single estimated figure, converting each
/// entry at the rate stored on that entry.
///
/// The rate comes from the entry, not from today, and that is the whole point.
/// Converting a net balance at today's rate answers a different question —
/// "what would settling cost right now" — and produces a number that cannot be
/// reconciled with the per-expense figures printed directly above it. Two
/// numbers on one screen that do not add up is worse than either question going
/// unanswered, and the "what do I owe now" question already has an exact answer
/// that needs no conversion at all: the per-currency balances.
///
/// So this one means "what this came to at the time", every part of it
/// traceable to a rate stamped on a specific expense on a specific day.
///
/// Rounding happens per entry rather than once at the end. That costs a minor
/// unit here and there against a mathematically ideal sum, and buys the thing
/// the figure exists for: it is the sum of the numbers the user can actually
/// see.
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
