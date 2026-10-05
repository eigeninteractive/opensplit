import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/money_format.dart';
import 'package:test/test.dart';

const inr = Currency(
  code: 'INR',
  exponent: 2,
  symbol: '₹',
  name: 'Indian Rupee',
);
const jpy = Currency(
  code: 'JPY',
  exponent: 0,
  symbol: '¥',
  name: 'Japanese Yen',
);
const kwd = Currency(
  code: 'KWD',
  exponent: 3,
  symbol: 'د.ك',
  name: 'Kuwaiti Dinar',
);

void main() {
  group('minorPerMajor', () {
    test('follows the exponent rather than assuming 100', () {
      expect(inr.minorPerMajor, 100);
      expect(jpy.minorPerMajor, 1);
      expect(kwd.minorPerMajor, 1000);
    });
  });

  group('formatPlain', () {
    test('renders each currency at its own precision', () {
      expect(inr.formatPlain(250000), '2500.00');
      expect(jpy.formatPlain(250000), '250000');
      expect(kwd.formatPlain(250000), '250.000');
    });

    test('pads the fraction', () {
      expect(inr.formatPlain(5), '0.05');
      expect(kwd.formatPlain(5), '0.005');
    });

    test('handles negatives', () {
      expect(inr.formatPlain(-2400), '-24.00');
      expect(jpy.formatPlain(-2400), '-2400');
    });
  });

  group('parseToMinor', () {
    test('reads major units into minor units', () {
      expect(inr.parseToMinor('2500.00'), 250000);
      expect(inr.parseToMinor('2500'), 250000);
      expect(inr.parseToMinor('0.05'), 5);
      expect(inr.parseToMinor('.5'), 50);
      expect(jpy.parseToMinor('2500'), 2500);
      expect(kwd.parseToMinor('2.5'), 2500);
    });

    test('takes a comma as the decimal point, and trims space', () {
      // A German or French number keyboard has no dot key. Read as grouping,
      // "12,50" would be a thousand and a quarter.
      expect(inr.parseToMinor(' 12,50 '), 1250);
      expect(kwd.parseToMinor('2,5'), 2500);
    });

    test(
      'refuses grouping, which means different things on different keyboards',
      () {
        expect(inr.parseToMinor('1,20,000.50'), isNull);
        expect(inr.parseToMinor('1,250'), isNull);
      },
    );

    test('refuses an amount too long to stay exact', () {
      expect(inr.parseToMinor('999999999999'), 99999999999900);
      expect(inr.parseToMinor('9999999999999'), isNull);
      expect(inr.parseToMinor('99999999999999999999'), isNull);
    });

    test('accepts every prefix of a valid amount as a field is typed', () {
      final shape = amountInputPattern(inr.exponent);
      for (final typed in ['', '1', '12', '12,', '12.5', '12,50']) {
        expect(shape.hasMatch(typed), isTrue, reason: typed);
      }
      for (final typed in ['12.505', '1.2.3', '-1', '1,250.00', 'abc']) {
        expect(shape.hasMatch(typed), isFalse, reason: typed);
      }
    });

    test('refuses more precision than the currency has', () {
      // 1.005 is not a representable rupee amount. Rounding it silently is how
      // money goes missing, so this is a parse failure the UI must surface.
      expect(inr.parseToMinor('1.005'), isNull);
      expect(jpy.parseToMinor('2500.5'), isNull);
      expect(kwd.parseToMinor('2.5005'), isNull);
    });

    test('rejects junk', () {
      expect(inr.parseToMinor(''), isNull);
      expect(inr.parseToMinor('abc'), isNull);
      expect(inr.parseToMinor('.'), isNull);
      expect(inr.parseToMinor('1.2.3'), isNull);
      expect(inr.parseToMinor('₹100'), isNull);
    });

    test('round-trips whatever it formats', () {
      for (final currency in [inr, jpy, kwd]) {
        for (final amount in [0, 1, 5, 99, 100, 12345, 999999999]) {
          expect(
            currency.parseToMinor(currency.formatPlain(amount)),
            amount,
            reason: '${currency.code} $amount',
          );
        }
      }
    });
  });
}
