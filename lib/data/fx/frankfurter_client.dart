import 'dart:convert';

import 'package:http/http.dart' as http;

/// One day's published rates from one base currency.
class FxSnapshot {
  const FxSnapshot({
    required this.base,
    required this.date,
    required this.rates,
  });

  final String base;

  /// ECB publication date at UTC midnight.
  final DateTime date;

  /// Units of each quote currency per one unit of [base].
  final Map<String, double> rates;
}

/// Reads ECB reference rates from Frankfurter.
///
/// Chosen because it needs no API key, sets CORS headers — so the web build can
/// call it directly with no proxy and no server cost — and republishes ECB data
/// rather than inventing its own. Rates are public reference data, so there is
/// nothing here worth authenticating.
///
/// The client is deliberately tolerant. It returns null on any failure rather
/// than throwing, because every caller's correct response to "no rate" is the
/// same: show the amount in the currency it was actually spent in, which is the
/// authoritative figure regardless.
class FrankfurterClient {
  FrankfurterClient({http.Client? client, this.timeout = _defaultTimeout})
    : _client = client ?? http.Client();

  static const _defaultTimeout = Duration(seconds: 6);
  static const _host = 'api.frankfurter.dev';

  /// Identifies the rates on an entry, so a stored snapshot can be traced.
  static const String source = 'ecb/frankfurter';

  /// The ECB reference set, as published at the time of writing.
  ///
  /// Advisory only — it exists to avoid spending a request on a base currency
  /// the service is known not to carry, not to override the server. If ECB adds
  /// a currency this list will simply be conservative until it is updated.
  ///
  /// Note what is absent: AED, KWD, BHD, LKR, NPR and VND are not ECB reference
  /// currencies, so groups defaulting to them get no converted estimate. Their
  /// balances are unaffected — those are per-currency and exact.
  static const Set<String> published = {
    'AUD',
    'BRL',
    'CAD',
    'CHF',
    'CNY',
    'CZK',
    'DKK',
    'EUR',
    'GBP',
    'HKD',
    'HUF',
    'IDR',
    'ILS',
    'INR',
    'ISK',
    'JPY',
    'KRW',
    'MXN',
    'MYR',
    'NOK',
    'NZD',
    'PHP',
    'PLN',
    'RON',
    'SEK',
    'SGD',
    'THB',
    'TRY',
    'USD',
    'ZAR',
  };

  final http.Client _client;
  final Duration timeout;

  /// Fetches the most recent publication for [base].
  ///
  /// [symbols] narrows the response; an empty set asks for everything. Symbols
  /// the service does not publish are simply absent from the result.
  Future<FxSnapshot?> latest({
    required String base,
    Iterable<String> symbols = const [],
  }) async {
    if (!published.contains(base)) return null;

    final wanted = symbols.where(published.contains).toSet()..remove(base);
    if (symbols.isNotEmpty && wanted.isEmpty) return null;

    final uri = Uri.https(_host, '/v1/latest', {
      'base': base,
      if (wanted.isNotEmpty) 'symbols': wanted.join(','),
    });

    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final rates = body['rates'];
      final date = body['date'];
      if (rates is! Map || date is! String) return null;

      return FxSnapshot(
        base: base,
        date: DateTime.parse('${date}T00:00:00Z'),
        rates: {
          for (final entry in rates.entries)
            if (entry.value is num)
              entry.key as String: (entry.value as num).toDouble(),
        },
      );
    } catch (_) {
      // Offline, DNS failure, timeout, the service being down, or a response
      // shape that changed under us. None of these are worth distinguishing:
      // the caller falls back to cache either way.
      return null;
    }
  }

  void close() => _client.close();
}
