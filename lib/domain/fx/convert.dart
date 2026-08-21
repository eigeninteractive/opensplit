import '../models/currency.dart';
import 'fx_quote.dart';

/// Converts [amountMinor] from one currency to another, for display only.
///
/// This is the only place in the app where a floating point number touches an
/// amount of money, and it is deliberately confined here. A converted figure is
/// never stored as a balance, never summed into one, and never written back as
/// an entry amount — it exists to answer "roughly how much is that in rupees?"
/// on a summary line and nowhere else. Balances stay authoritative per currency,
/// because an exchange rate is an opinion and a debt is not.
///
/// The exponents on both sides are read from the [Currency] rows rather than
/// assumed, so converting ¥5,000 (exponent 0) into ₹ (exponent 2) produces the
/// right magnitude instead of being wrong by a factor of a hundred.
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
///
/// Returns null when the quote does not describe this conversion, rather than
/// silently converting with the wrong rate — a mismatched pair is a bug in the
/// caller and hiding it would produce a plausible, wrong number.
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
