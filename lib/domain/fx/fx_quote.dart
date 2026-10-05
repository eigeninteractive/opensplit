import 'package:freezed_annotation/freezed_annotation.dart';

part 'fx_quote.freezed.dart';

/// How many days old a rate may be and still answer for a day. A week covers
/// every weekend and every ECB holiday; older than that, the rate describes
/// some other time. The server holds the same rule as `STALE_AFTER_DAYS` in
/// `server/src/do/fx/index.ts`, so the days it fills are the days this asks
/// for.
const rateStaleAfterDays = 7;

/// A rate for converting [base] into [quote], as published on [date].
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
  bool isBehind(DateTime nowUtc) {
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    return date.isBefore(today);
  }
}
