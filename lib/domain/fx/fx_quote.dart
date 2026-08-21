import 'package:freezed_annotation/freezed_annotation.dart';

part 'fx_quote.freezed.dart';

/// A rate for converting [base] into [quote], as published on [date].
///
/// Carries its publication date because that is what makes a converted figure
/// honest: ECB rates are published once per business day, so any conversion the
/// app shows is at best hours old and over a weekend is days old. The screen
/// says so rather than presenting a stale number as current.
@freezed
abstract class FxQuote with _$FxQuote {
  const factory FxQuote({
    /// The currency being converted from.
    required String base,

    /// The currency being converted to.
    required String quote,

    /// Units of [quote] per one unit of [base].
    required double rate,

    /// ECB publication date, at UTC midnight. Not the time it was fetched.
    required DateTime date,

    /// Provenance, stored on the entry alongside the rate so a figure can
    /// always be traced back to who said so.
    required String source,
  }) = _FxQuote;

  const FxQuote._();

  /// Whether a newer publication is likely to exist.
  ///
  /// Only ever used to decide whether to spend a network call. It is never a
  /// reason to withhold a conversion: a rate from last Friday converts a
  /// dinner bill perfectly well, and refusing to show anything because the
  /// number is a day old would be worse than showing it with its date.
  bool isBehind(DateTime nowUtc) {
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    return date.isBefore(today);
  }
}
