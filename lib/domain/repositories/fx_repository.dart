import '../fx/fx_quote.dart';

/// Supplies exchange rates for display-only conversion.
///
/// Every method is total: a rate is a convenience, and no implementation may
/// throw into a caller or block one on the network. Entry creation in
/// particular must complete offline, at an airport, with the rate service down
/// — in which case the entry is simply stored without a snapshot, which the
/// data model already allows.
abstract interface class FxRepository {
  /// The best rate available for [base] → [quote], cache first.
  ///
  /// Null when no rate has ever been cached for the pair and none can be
  /// fetched — including for currencies the rate source does not publish at
  /// all, which is a normal outcome rather than an error.
  Future<FxQuote?> quote({required String base, required String quote});

  /// Warms the cache for a set of pairs, best effort.
  ///
  /// Called when a group is opened, so that the rate is already local by the
  /// time anyone adds an expense in a second currency.
  Future<void> warm({required String base, required Iterable<String> quotes});
}
