import 'package:drift/drift.dart';

import '../../domain/fx/fx_quote.dart';
import '../../domain/repositories/fx_repository.dart';
import '../local/database.dart';
import 'frankfurter_client.dart';

/// Cache-first exchange rates, backed by the local `fx_rates` table.
///
/// The cache is the primary source and the network is the refresher, not the
/// other way around. That ordering is not defensive programming: the rate
/// service is a free public endpoint with no uptime commitment, and an expense
/// app is used on aeroplanes and foreign SIMs. A design that reads through to
/// the network would show no conversion at all precisely when someone is most
/// likely to be spending in a second currency.
///
/// Rates are only ever used for display. Nothing here can affect a balance.
class DriftFxRepository implements FxRepository {
  DriftFxRepository(
    this._db,
    this._client, {
    DateTime Function()? clock,
    this.retryAfter = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FrankfurterClient _client;
  final DateTime Function() _clock;

  /// How long to wait before trying again after a failed fetch.
  ///
  /// Without this, every screen that wants a conversion re-attempts on every
  /// build while the service is down, which is both pointless and rude to a
  /// free endpoint.
  final Duration retryAfter;

  DateTime? _nextAttempt;

  @override
  Future<FxQuote?> quote({required String base, required String quote}) async {
    final now = _clock().toUtc();

    if (base == quote) {
      return FxQuote(
        base: base,
        quote: quote,
        rate: 1,
        date: DateTime.utc(now.year, now.month, now.day),
        source: 'identity',
      );
    }

    final cached = await _cached(base, quote);
    if (cached != null && !cached.isBehind(now)) return cached;

    // Either nothing cached or today's publication may exist. Try once, then
    // answer with whatever we ended up holding — which may still be the older
    // cached rate, and that is a perfectly good answer.
    await warm(base: quote, quotes: [base]);
    return await _cached(base, quote) ?? cached;
  }

  @override
  Future<void> warm({
    required String base,
    required Iterable<String> quotes,
  }) async {
    final wanted = quotes.where((code) => code != base).toSet();
    if (wanted.isEmpty) return;

    final now = _clock().toUtc();
    if (_nextAttempt != null && now.isBefore(_nextAttempt!)) return;

    final snapshot = await _client.latest(base: base, symbols: wanted);
    if (snapshot == null) {
      _nextAttempt = now.add(retryAfter);
      return;
    }
    _nextAttempt = null;

    // Both directions are written from the one response.
    //
    // A group summarising in INR needs USD→INR, but asking for base=INR
    // returns INR→USD — and one request covering every currency the group
    // holds is far better than one request per currency. The reciprocal is not
    // bit-identical to what a base=USD request would return, which does not
    // matter for a figure that is labelled an estimate and never stored as a
    // balance.
    await _db.batch((batch) {
      for (final entry in snapshot.rates.entries) {
        if (entry.value <= 0 || !entry.value.isFinite) continue;

        batch.insert(
          _db.fxRates,
          FxRatesCompanion.insert(
            date: _isoDate(snapshot.date),
            base: snapshot.base,
            quote: entry.key,
            rate: entry.value,
          ),
          mode: InsertMode.insertOrReplace,
        );
        batch.insert(
          _db.fxRates,
          FxRatesCompanion.insert(
            date: _isoDate(snapshot.date),
            base: entry.key,
            quote: snapshot.base,
            rate: 1 / entry.value,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// The most recently published cached rate for a pair, whatever its age.
  Future<FxQuote?> _cached(String base, String quote) async {
    final row =
        await (_db.select(_db.fxRates)
              ..where((t) => t.base.equals(base) & t.quote.equals(quote))
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;

    return FxQuote(
      base: row.base,
      quote: row.quote,
      rate: row.rate,
      date: DateTime.parse('${row.date}T00:00:00Z'),
      source: FrankfurterClient.source,
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
