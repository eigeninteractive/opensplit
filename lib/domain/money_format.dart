import 'models/currency.dart';

/// Currencies conventionally grouped in the Indian system — the last three
/// digits, then pairs: 1,23,45,678 rather than 12,345,678.
const _indianGrouping = {'INR', 'NPR', 'LKR', 'PKR', 'BDT'};

/// Formats [amountMinor] for display.
String formatMoney(
  Currency? currency,
  int amountMinor, {
  bool withSymbol = true,
  bool alwaysSigned = false,
}) {
  if (currency == null) return amountMinor.toString();

  final negative = amountMinor < 0;
  final abs = amountMinor.abs();
  final major = abs ~/ currency.minorPerMajor;
  final minor = abs % currency.minorPerMajor;

  final grouped = _group(
    major.toString(),
    indian: _indianGrouping.contains(currency.code),
  );
  final digits = currency.exponent == 0
      ? grouped
      : '$grouped.${minor.toString().padLeft(currency.exponent, '0')}';

  final sign = negative
      ? '-'
      : alwaysSigned && amountMinor > 0
      ? '+'
      : '';
  final symbol = withSymbol ? (currency.symbol ?? '${currency.code} ') : '';

  return '$sign$symbol$digits';
}

/// Formats an amount without its sign, for use where the direction is carried
/// by words instead — "you owe" / "owes you".
String formatMoneyAbs(Currency? currency, int amountMinor) =>
    formatMoney(currency, amountMinor.abs());

String _group(String digits, {required bool indian}) {
  if (digits.length <= 3) return digits;

  if (!indian) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  // Indian: last three digits stand alone, everything above is in pairs.
  final tail = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${parts.join(',')},$tail';
}
