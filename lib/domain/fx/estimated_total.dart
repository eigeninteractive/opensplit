import '../models/currency.dart';
import 'convert.dart';
import 'fx_quote.dart';

/// A single figure standing in for money held in several currencies.
///
/// Always an estimate, and shaped so a caller cannot forget that: it carries
/// the date of the oldest rate that went into it, and the currencies it could
/// not convert at all. A screen that shows [amountMinor] without also showing
/// [asOf] is misrepresenting it.
class EstimatedTotal {
  const EstimatedTotal({
    required this.amountMinor,
    required this.currency,
    required this.asOf,
    required this.unconverted,
  });

  /// The converted sum, in [currency]'s minor units.
  final int amountMinor;

  /// The currency everything was converted into — the group's default.
  final String currency;

  /// Publication date of the oldest rate used. The estimate is at best this
  /// fresh, so this is the date a screen should quote.
  final DateTime asOf;

  /// Currencies excluded because no rate was available.
  ///
  /// Not an error: ECB reference rates do not cover AED, KWD, BHD, LKR, NPR or
  /// VND, so a group holding those will always have entries here. The figure
  /// stays honest by naming what it left out instead of quietly under-reporting.
  final List<String> unconverted;

  bool get isComplete => unconverted.isEmpty;
}

/// Folds per-currency amounts into one estimated figure.
///
/// Pure, so the interesting cases — a missing rate, a rate from last week, a
/// currency with a different exponent — are testable without a network or a
/// database.
EstimatedTotal? estimateTotal({
  required Map<String, int> perCurrencyMinor,
  required String target,
  required Map<String, Currency> currencies,
  required Map<String, FxQuote> quotes,
}) {
  final targetCurrency = currencies[target];
  if (targetCurrency == null) return null;

  var total = 0;
  DateTime? oldest;
  final unconverted = <String>[];
  var convertedAny = false;

  final codes = perCurrencyMinor.keys.toList()..sort();
  for (final code in codes) {
    final amount = perCurrencyMinor[code]!;
    if (amount == 0) continue;

    if (code == target) {
      total += amount;
      convertedAny = true;
      continue;
    }

    final from = currencies[code];
    final quote = quotes[code];
    if (from == null || quote == null) {
      unconverted.add(code);
      continue;
    }

    final converted = convertWith(
      amountMinor: amount,
      from: from,
      to: targetCurrency,
      quote: quote,
    );
    if (converted == null) {
      unconverted.add(code);
      continue;
    }

    total += converted;
    convertedAny = true;
    if (oldest == null || quote.date.isBefore(oldest)) oldest = quote.date;
  }

  // Nothing was converted, so there is no estimate to make — as distinct from
  // an estimate of zero, which is a real and different answer.
  if (!convertedAny) return null;

  return EstimatedTotal(
    amountMinor: total,
    currency: target,
    // Only same-currency amounts contributed, so the figure is exact and its
    // freshness is not in question.
    asOf: oldest ?? DateTime.utc(1970),
    unconverted: unconverted,
  );
}
