import 'package:opensplit/domain/models/currency.dart';
import 'package:test/test.dart';

const inr = Currency(code: 'INR', exponent: 2, symbol: '₹', name: 'Indian Rupee');
const jpy = Currency(code: 'JPY', exponent: 0, symbol: '¥', name: 'Japanese Yen');
const kwd = Currency(code: 'KWD', exponent: 3, symbol: 'د.ك', name: 'Kuwaiti Dinar');

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

    test('strips grouping separators and surrounding space', () {
      expect(inr.parseToMinor(' 1,20,000.50 '), 12000050);
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
