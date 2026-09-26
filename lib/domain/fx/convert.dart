import '../models/currency.dart';
import 'fx_quote.dart';

/// Converts [amountMinor] from one currency to another, for display only.
int convertMinor({
  required int amountMinor,
  required Currency from,
  required Currency to,
  required double rate,
}) {
  // Identity is exact and must not round-trip through a double: converting INR
  // to INR has to return the same integer it was given, always.
  if (from.code == to.code) return amountMinor;

  final major = amountMinor / from.minorPerMajor;
  return (major * rate * to.minorPerMajor).round();
}

/// Convenience over [convertMinor] for a quote that already names its pair.
int? convertWith({
  required int amountMinor,
  required Currency from,
  required Currency to,
  required FxQuote quote,
}) {
  if (from.code == to.code) return amountMinor;
  if (quote.base != from.code || quote.quote != to.code) return null;
  return convertMinor(
    amountMinor: amountMinor,
    from: from,
    to: to,
    rate: quote.rate,
  );
}
