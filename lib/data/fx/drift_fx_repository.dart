import 'package:drift/drift.dart';

import '../../domain/fx/fx_quote.dart';
import '../../domain/repositories/fx_repository.dart';
import '../local/database.dart';

/// Exchange rates read from the locally mirrored pivot table.
///
/// Every rate is expressed against USD, so converting A into B is one division
/// of two independently looked-up rows. That is the whole reason there is no
/// notion of a "supported pair" anywhere in this app: either a currency has a
/// published rate on or before the date in question, or it does not, and the
/// answer is the same shape for all 16 of them.
class DriftFxRepository implements FxRepository {
  DriftFxRepository(this._db);

  final AppDatabase _db;

  @override
  Future<FxQuote?> quote({
    required String base,
    required String quote,
    required DateTime asOf,
  }) async {
    final day = isoDate(asOf);

    if (base == quote) {
      return FxQuote(
        base: base,
        quote: quote,
        rate: 1,
        date: asOf,
        source: 'identity',
      );
    }

    final from = await _rateOn(base, day);
    final to = await _rateOn(quote, day);
    if (from == null || to == null) return null;
    if (from.rate <= 0) return null;

    return FxQuote(
      base: base,
      quote: quote,
      rate: to.rate / from.rate,
      // The older of the two publications: a figure is only as current as the
      // stalest number that went into it, and claiming otherwise would
      // overstate how fresh the estimate is.
      date: _parseDay(from.asOf.compareTo(to.asOf) <= 0 ? from.asOf : to.asOf),
      source: from.source == to.source
          ? from.source
          : '${from.source} + ${to.source}',
    );
  }

  /// The most recent publication for a currency on or before [day].
  Future<FxRateRow?> _rateOn(String currency, String day) =>
      (_db.select(_db.fxRates)
            ..where(
              (t) =>
                  t.currency.equals(currency) &
                  t.asOf.isSmallerOrEqualValue(day),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.asOf)])
            ..limit(1))
          .getSingleOrNull();

  static DateTime _parseDay(String day) => DateTime.parse('${day}T00:00:00Z');
}

/// Formats a date the way the rate table keys them.
String isoDate(DateTime date) {
  final utc = date.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}
