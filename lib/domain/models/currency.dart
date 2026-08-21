import 'package:freezed_annotation/freezed_annotation.dart';

part 'currency.freezed.dart';

/// An ISO 4217 currency and — critically — its exponent.
///
/// The exponent is the number of decimal digits in the minor unit. It is NOT
/// always 2: JPY and KRW are 0, KWD and BHD are 3. Hardcoding `* 100` anywhere
/// in this app is a bug that will ship, so every conversion between a
/// user-facing amount and stored minor units goes through a [Currency].
@freezed
abstract class Currency with _$Currency {
  const factory Currency({
    /// ISO 4217 alphabetic code, e.g. `INR`.
    required String code,

    /// Digits after the decimal point in the minor unit.
    required int exponent,

    /// Display symbol, e.g. `₹`. May be absent for obscure currencies.
    String? symbol,

    required String name,
  }) = _Currency;

  const Currency._();

  /// Minor units in one major unit: 100 for INR, 1 for JPY, 1000 for KWD.
  int get minorPerMajor {
    var factor = 1;
    for (var i = 0; i < exponent; i++) {
      factor *= 10;
    }
    return factor;
  }

  /// Formats [amountMinor] as a plain decimal string, without a symbol.
  ///
  /// `250000` in INR is `2500.00`; in JPY it is `250000`; in KWD `250.000`.
  String formatPlain(int amountMinor) {
    final negative = amountMinor < 0;
    final abs = amountMinor.abs();
    if (exponent == 0) return '${negative ? '-' : ''}$abs';

    final major = abs ~/ minorPerMajor;
    final minor = abs % minorPerMajor;
    final fraction = minor.toString().padLeft(exponent, '0');
    return '${negative ? '-' : ''}$major.$fraction';
  }

  /// Parses user input in major units into minor units.
  ///
  /// Returns null when [input] is not a well-formed amount for this currency,
  /// including when it carries more decimal places than the currency has —
  /// `1.005` is not a representable INR amount and silently rounding it is how
  /// money quietly goes missing.
  int? parseToMinor(String input) {
    final trimmed = input.trim().replaceAll(',', '');
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'^(-)?(\d*)(?:\.(\d*))?$').firstMatch(trimmed);
    if (match == null) return null;

    final sign = match.group(1) == null ? 1 : -1;
    final majorText = match.group(2) ?? '';
    final fractionText = match.group(3) ?? '';
    if (majorText.isEmpty && fractionText.isEmpty) return null;
    if (fractionText.length > exponent) return null;

    final major = majorText.isEmpty ? 0 : int.parse(majorText);
    final fraction = fractionText.isEmpty
        ? 0
        : int.parse(fractionText.padRight(exponent, '0'));

    return sign * (major * minorPerMajor + fraction);
  }
}
