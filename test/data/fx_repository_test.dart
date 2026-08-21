import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opensplit/data/fx/drift_fx_repository.dart';
import 'package:opensplit/data/fx/frankfurter_client.dart';
import 'package:opensplit/data/local/database.dart';

/// A stand-in for the rate service that records what was asked of it.
class _Service {
  static const _default = {'USD': 0.0114};

  String date = '2026-08-20';
  Map<String, double> rates = _default;
  int calls = 0;
  bool down = false;
  Uri? lastUri;

  http.Client get client => MockClient((request) async {
    calls++;
    lastUri = request.url;
    if (down) return http.Response('nope', 503);
    return http.Response(
      jsonEncode({
        'amount': 1.0,
        'base': request.url.queryParameters['base'],
        'date': date,
        'rates': rates,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  late AppDatabase db;
  late _Service service;
  late DriftFxRepository repository;
  var now = DateTime.utc(2026, 8, 20, 12);

  setUp(() async {
    // Reset the clock too: tests below move it forwards, and a later test
    // starting in the future would silently invert the backoff comparison.
    now = DateTime.utc(2026, 8, 20, 12);
    db = AppDatabase(NativeDatabase.memory());
    service = _Service();
    repository = DriftFxRepository(
      db,
      FrankfurterClient(client: service.client),
      clock: () => now,
    );
  });

  tearDown(() async => db.close());

  test('fetches once and answers from cache afterwards', () async {
    final first = await repository.quote(base: 'USD', quote: 'INR');
    expect(first!.rate, closeTo(87.7, 0.1));
    expect(service.calls, 1);

    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 1, reason: 'a cached same-day rate needs no request');
  });

  test('one request covers both directions of a pair', () async {
    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 1);

    // The reciprocal was stored from the same response, so this must not spend
    // a second call — that is the whole reason warm() fetches by group default.
    final reverse = await repository.quote(base: 'INR', quote: 'USD');
    expect(reverse!.rate, closeTo(0.0114, 0.0001));
    expect(service.calls, 1);
  });

  test('serves a stale cached rate when the service is down', () async {
    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 1);

    service.down = true;
    now = DateTime.utc(2026, 8, 25, 12);

    final stale = await repository.quote(base: 'USD', quote: 'INR');
    expect(
      stale,
      isNotNull,
      reason: 'an old rate beats no conversion at all when offline',
    );
    expect(stale!.date, DateTime.utc(2026, 8, 20));
  });

  test('backs off rather than retrying a down service on every read', () async {
    service.down = true;
    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 1);

    await repository.quote(base: 'USD', quote: 'INR');
    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 1, reason: 'inside the backoff window');

    now = DateTime.utc(2026, 8, 20, 12, 11);
    await repository.quote(base: 'USD', quote: 'INR');
    expect(service.calls, 2, reason: 'the window has passed');
  });

  test('returns null for a currency ECB does not publish', () async {
    final quote = await repository.quote(base: 'AED', quote: 'INR');
    expect(quote, isNull);
    expect(
      service.calls,
      0,
      reason: 'no point spending a request on a base the source never carries',
    );
  });

  test('identity is exact and costs nothing', () async {
    final quote = await repository.quote(base: 'INR', quote: 'INR');
    expect(quote!.rate, 1);
    expect(service.calls, 0);
  });

  test('a newer publication supersedes the cached one', () async {
    await repository.quote(base: 'USD', quote: 'INR');

    now = DateTime.utc(2026, 8, 21, 18);
    service
      ..date = '2026-08-21'
      ..rates = {'USD': 0.0100};

    final fresh = await repository.quote(base: 'USD', quote: 'INR');
    expect(fresh!.date, DateTime.utc(2026, 8, 21));
    expect(fresh.rate, closeTo(100, 0.1));
  });

  test('warm asks for every currency in one request', () async {
    await repository.warm(base: 'INR', quotes: ['USD', 'EUR', 'JPY']);
    expect(service.calls, 1);
    final symbols = service.lastUri!.queryParameters['symbols']!.split(',');
    expect(symbols, containsAll(['USD', 'EUR', 'JPY']));
  });

  test('ignores a non-positive rate rather than caching nonsense', () async {
    service.rates = {'USD': 0, 'EUR': -1};
    await repository.warm(base: 'INR', quotes: ['USD', 'EUR']);
    expect(await repository.quote(base: 'USD', quote: 'INR'), isNull);
  });
}
