// `isNull` here is Drift's column predicate, which collides with the
// matcher of the same name.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/fx/drift_fx_repository.dart';
import 'package:opensplit/data/local/database.dart';

void main() {
  late AppDatabase db;
  late DriftFxRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftFxRepository(db);
  });

  tearDown(() async => db.close());

  /// Rates are units per USD, exactly as the server stores them.
  Future<void> publish(
    String asOf,
    Map<String, double> rates, {
    String source = 'test',
  }) async {
    await db.batch((batch) {
      for (final entry in rates.entries) {
        batch.insert(
          db.fxRates,
          FxRatesCompanion.insert(
            asOf: asOf,
            currency: entry.key,
            rate: entry.value,
            source: source,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  group('pivot lookup', () {
    test('derives a pair neither side of which is the pivot', () async {
      // 3.6725 AED and 95.7 INR to the dollar.
      await publish('2026-08-21', {'USD': 1, 'AED': 3.6725, 'INR': 95.7});

      final quote = await repository.quote(
        base: 'AED',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );
      expect(quote!.rate, closeTo(95.7 / 3.6725, 1e-9));
    });

    test('identity is exact', () async {
      final quote = await repository.quote(
        base: 'INR',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );
      expect(quote!.rate, 1);
    });

    test('a currency with no published rate yields null', () async {
      await publish('2026-08-21', {'USD': 1, 'INR': 95.7});
      expect(
        await repository.quote(
          base: 'KWD',
          quote: 'INR',
          asOf: DateTime.utc(2026, 8, 21),
        ),
        isNull,
      );
    });
  });

  group('as of a date', () {
    test('a backdated entry uses that date, not the newest rate', () async {
      await publish('2026-08-14', {'USD': 1, 'INR': 95.43});
      await publish('2026-08-21', {'USD': 1, 'INR': 95.70});

      final then = await repository.quote(
        base: 'USD',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 14),
      );
      final now = await repository.quote(
        base: 'USD',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );

      // The whole point: recording last Tuesday's dinner today must not price
      // it at today's rate.
      expect(then!.rate, closeTo(95.43, 1e-9));
      expect(now!.rate, closeTo(95.70, 1e-9));
    });

    test('a weekend falls back to the last publication before it', () async {
      // ECB publishes on business days. 2026-08-16 was a Sunday.
      await publish('2026-08-14', {'USD': 1, 'INR': 95.43});

      final quote = await repository.quote(
        base: 'USD',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 16),
      );
      expect(quote!.rate, closeTo(95.43, 1e-9));
      expect(
        quote.date,
        DateTime.utc(2026, 8, 14),
        reason: 'the figure is only as fresh as the rate behind it',
      );
    });

    test('never reaches forward for a rate published later', () async {
      await publish('2026-08-21', {'USD': 1, 'INR': 95.70});

      // An entry backdated before any publication we hold. Answering with a
      // later rate would be inventing history.
      expect(
        await repository.quote(
          base: 'USD',
          quote: 'INR',
          asOf: DateTime.utc(2026, 8, 1),
        ),
        isNull,
      );
    });

    test('reports the older of the two publications used', () async {
      await publish('2026-08-14', {'AED': 3.6725});
      await publish('2026-08-21', {'USD': 1, 'INR': 95.70});

      final quote = await repository.quote(
        base: 'AED',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );
      expect(quote!.date, DateTime.utc(2026, 8, 14));
    });
  });

  group('provenance', () {
    test('names both providers when a pair spans two of them', () async {
      // Exactly what the server's waterfall produces: ECB covers INR, the
      // other provider covers AED, and one estimate uses both.
      await publish('2026-08-21', {'INR': 95.7}, source: 'Frankfurter (ECB)');
      await publish('2026-08-21', {
        'AED': 3.6725,
      }, source: 'ExchangeRate-API (open)');

      final quote = await repository.quote(
        base: 'AED',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );
      expect(quote!.source, contains('Frankfurter'));
      expect(quote.source, contains('ExchangeRate-API'));
    });

    test('names one provider when it supplied both sides', () async {
      await publish('2026-08-21', {
        'USD': 1,
        'INR': 95.7,
      }, source: 'Frankfurter (ECB)');
      final quote = await repository.quote(
        base: 'USD',
        quote: 'INR',
        asOf: DateTime.utc(2026, 8, 21),
      );
      expect(quote!.source, 'Frankfurter (ECB)');
    });
  });
}
