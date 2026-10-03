/// Decimal numbers as people type them into a field.
library;

import 'split/allocation.dart';

/// A non-negative decimal as typed, with either `.` or `,` as its point: a
/// phone's number keyboard shows whichever the device's region uses. The
/// whole part is group 1 and the fraction group 2, empty when absent.
///
/// Matches every prefix of a valid number too, including the empty string,
/// so it can guard a field keystroke by keystroke.
RegExp decimalInputPattern({
  required int wholeDigits,
  required int fractionDigits,
}) => RegExp(
  fractionDigits == 0
      ? '^(\\d{0,$wholeDigits})()\$'
      : '^(\\d{0,$wholeDigits})(?:[.,](\\d{0,$fractionDigits}))?\$',
);

/// A percentage as typed: up to three whole digits, and six decimals, the
/// precision a share's weight is stored to.
final percentInputPattern = decimalInputPattern(
  wholeDigits: 3,
  fractionDigits: 6,
);

/// A typed percentage in millionths, or null for anything that is not one.
int? parsePercentMicros(String text) {
  final match = percentInputPattern.firstMatch(text.trim());
  if (match == null) return null;
  final whole = match.group(1) ?? '';
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  return (whole.isEmpty ? 0 : int.parse(whole)) * weightScale +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(6, '0')));
}

/// A percentage in millionths as somebody would type it: `12.5`, not
/// `12.500000`.
String formatPercentMicros(int micros) {
  final whole = micros ~/ weightScale;
  final fraction = micros % weightScale;
  if (fraction == 0) return '$whole';
  final decimals = fraction
      .toString()
      .padLeft(6, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return '$whole.$decimals';
}
