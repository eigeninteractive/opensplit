import '../fx/fx_quote.dart';

/// Supplies exchange rates for display-only conversion.
///
/// Reads only. Rates are fetched centrally by the server and reach the device
/// through sync, so nothing here touches the network: a conversion is available
/// offline, and every member of a group converts with the same numbers.
///
/// Every method is total. A rate is a convenience, and no implementation may
/// throw into a caller or block one — entry creation in particular must
/// complete on a plane, in which case the entry is stored without a snapshot,
/// which the data model already allows.
abstract interface class FxRepository {
  /// The rate for converting [base] into [quote] as it stood on [asOf].
  ///
  /// Uses the most recent publication on or before [asOf], never a later one.
  /// Backdating an expense to last Tuesday must use last Tuesday's rate; using
  /// today's would silently restate history every time the market moved. It
  /// also disposes of weekends and holidays without any calendar logic: there
  /// is no Sunday publication, and Friday's is the correct answer for Sunday.
  ///
  /// Null when either side has no published rate on or before that date, which
  /// is an ordinary outcome rather than an error.
  Future<FxQuote?> quote({
    required String base,
    required String quote,
    required DateTime asOf,
  });
}
