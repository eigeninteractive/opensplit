import 'package:drift/drift.dart';

import '../../domain/calendar_date.dart';
import '../../domain/fx/fx_quote.dart';
import '../local/database.dart';

/// Exchange rates read from the locally mirrored pivot table.
class DriftFxRepository {
  DriftFxRepository(this._db);

  final AppDatabase _db;

  /// The rate for converting [base] into [quote] as it stood on [asOf].
  Future<FxQuote?> quote({
    required String base,
    required String quote,
    required DateTime asOf,
  }) async {
    final day = calendarDate(asOf);

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
      date: parseCalendarDate(
        from.asOf.compareTo(to.asOf) <= 0 ? from.asOf : to.asOf,
      ),
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
}
