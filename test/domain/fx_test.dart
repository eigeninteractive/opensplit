import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/domain/fx/convert.dart';
import 'package:opensplit/domain/fx/estimated_total.dart';
import 'package:opensplit/domain/fx/fx_quote.dart';
import 'package:opensplit/domain/models/currency.dart';

const inr = Currency(code: 'INR', exponent: 2, symbol: '₹', name: 'Rupee');
const usd = Currency(code: 'USD', exponent: 2, symbol: r'$', name: 'Dollar');
const jpy = Currency(code: 'JPY', exponent: 0, symbol: '¥', name: 'Yen');
const kwd = Currency(code: 'KWD', exponent: 3, symbol: 'د.ك', name: 'Dinar');

FxQuote quote(String base, String to, double rate, {DateTime? date}) => FxQuote(
  base: base,
  quote: to,
  rate: rate,
  date: date ?? DateTime.utc(2026, 8, 20),
  source: 'test',
);

void main() {
  group('convertMinor', () {
    test('same currency is exact and never touches a double', () {
      // Deliberately a value a double cannot represent exactly once divided.
      expect(
        convertMinor(amountMinor: 333333, from: inr, to: inr, rate: 1.0),
        333333,
      );
    });

    test('respects the exponent on both sides', () {
      // ¥5000 (exponent 0) at 0.56 INR per JPY is ₹2800.00 -> 280000 minor.
      expect(
        convertMinor(amountMinor: 5000, from: jpy, to: inr, rate: 0.56),
        280000,
      );
      // $10.00 at 0.31 KWD per USD is 3.100 KWD -> 3100 minor (exponent 3).
      expect(
        convertMinor(amountMinor: 1000, from: usd, to: kwd, rate: 0.31),
        3100,
      );
    });

    test('a wrong exponent assumption would be off by a factor of 100', () {
      // Guards the specific bug the currencies table exists to prevent: if JPY
      // were treated as exponent 2 this would come out at 2800 rather than
      // 280000.
      final converted = convertMinor(
        amountMinor: 5000,
        from: jpy,
        to: inr,
        rate: 0.56,
      );
      expect(converted, isNot(2800));
    });

    test('negative amounts convert symmetrically', () {
      expect(
        convertMinor(amountMinor: -1000, from: usd, to: inr, rate: 87.5),
        -convertMinor(amountMinor: 1000, from: usd, to: inr, rate: 87.5),
      );
    });
  });

  group('convertWith', () {
    test('refuses a quote for the wrong pair rather than guessing', () {
      expect(
        convertWith(
          amountMinor: 1000,
          from: usd,
          to: inr,
          quote: quote('EUR', 'INR', 95),
        ),
        isNull,
      );
    });
  });

  group('estimateTotal', () {
    const currencies = {'INR': inr, 'USD': usd, 'JPY': jpy};

    test('sums converted balances into the target currency', () {
      final total = estimateTotal(
        perCurrencyMinor: {'INR': 100000, 'USD': 1000},
        target: 'INR',
        currencies: currencies,
        quotes: {'USD': quote('USD', 'INR', 87.5)},
      );
      expect(total!.amountMinor, 100000 + 87500);
      expect(total.isComplete, isTrue);
    });

    test('names what it could not convert instead of under-reporting', () {
      final total = estimateTotal(
        perCurrencyMinor: {'INR': 100000, 'USD': 1000},
        target: 'INR',
        currencies: currencies,
        quotes: const {},
      );
      expect(total!.amountMinor, 100000);
      expect(total.isComplete, isFalse);
      expect(total.unconverted, ['USD']);
    });

    test('reports the oldest rate it used, not the newest', () {
      final total = estimateTotal(
        perCurrencyMinor: {'USD': 1000, 'JPY': 5000},
        target: 'INR',
        currencies: currencies,
        quotes: {
          'USD': quote('USD', 'INR', 87.5, date: DateTime.utc(2026, 8, 20)),
          'JPY': quote('JPY', 'INR', 0.56, date: DateTime.utc(2026, 8, 14)),
        },
      );
      // Quoting the fresher date would overstate how current the figure is.
      expect(total!.asOf, DateTime.utc(2026, 8, 14));
    });

    test('returns null when nothing could be converted at all', () {
      // Distinct from an estimate of zero: the screen must say nothing rather
      // than claim the user is settled.
      final total = estimateTotal(
        perCurrencyMinor: {'USD': 1000},
        target: 'INR',
        currencies: currencies,
        quotes: const {},
      );
      expect(total, isNull);
    });

    test('ignores zero balances so a settled currency adds no noise', () {
      final total = estimateTotal(
        perCurrencyMinor: {'INR': 5000, 'USD': 0},
        target: 'INR',
        currencies: currencies,
        quotes: const {},
      );
      expect(total!.isComplete, isTrue);
      expect(total.unconverted, isEmpty);
    });
  });

  group('FxQuote.isBehind', () {
    test('a rate published today is current', () {
      final q = quote('USD', 'INR', 87.5, date: DateTime.utc(2026, 8, 21));
      expect(q.isBehind(DateTime.utc(2026, 8, 21, 18)), isFalse);
    });

    test('yesterday'
        's rate is behind', () {
      final q = quote('USD', 'INR', 87.5, date: DateTime.utc(2026, 8, 20));
      expect(q.isBehind(DateTime.utc(2026, 8, 21, 9)), isTrue);
    });
  });
}
