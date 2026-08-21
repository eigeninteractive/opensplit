import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/settle/upi.dart';
import 'package:test/test.dart';

const inr = Currency(
  code: 'INR',
  exponent: 2,
  symbol: '₹',
  name: 'Indian Rupee',
);
const usd = Currency(code: 'USD', exponent: 2, symbol: r'$', name: 'US Dollar');

void main() {
  group('isValidUpiVpa', () {
    test('accepts ordinary handles', () {
      expect(isValidUpiVpa('priya@okhdfcbank'), isTrue);
      expect(isValidUpiVpa('ravi.kumar-1_x@ybl'), isTrue);
    });

    test('rejects malformed handles', () {
      expect(isValidUpiVpa(null), isFalse);
      expect(isValidUpiVpa(''), isFalse);
      expect(isValidUpiVpa('priya'), isFalse);
      expect(isValidUpiVpa('priya@'), isFalse);
      expect(isValidUpiVpa('@okhdfcbank'), isFalse);
      expect(
        isValidUpiVpa('a@okhdfcbank'),
        isFalse,
        reason: 'handle too short',
      );
      expect(
        isValidUpiVpa('priya@bank1'),
        isFalse,
        reason: 'psp is letters only',
      );
    });
  });

  group('buildUpiPaymentUri', () {
    test('builds a payable intent for an INR settlement', () {
      final uri = buildUpiPaymentUri(
        payeeVpa: 'priya@okhdfcbank',
        payeeName: 'Priya',
        amountMinor: 60000,
        currency: inr,
      );

      expect(uri, isNotNull);
      expect(uri!.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters['pa'], 'priya@okhdfcbank');
      expect(uri.queryParameters['pn'], 'Priya');
      expect(uri.queryParameters['am'], '600.00');
      expect(uri.queryParameters['cu'], 'INR');
      expect(uri.queryParameters['tn'], 'OpenSplit settlement');
    });

    test('offers no handoff outside INR', () {
      expect(
        buildUpiPaymentUri(
          payeeVpa: 'priya@okhdfcbank',
          payeeName: 'Priya',
          amountMinor: 60000,
          currency: usd,
        ),
        isNull,
      );
    });

    test('offers no handoff without a valid payee handle', () {
      expect(
        buildUpiPaymentUri(
          payeeVpa: null,
          payeeName: 'Priya',
          amountMinor: 60000,
          currency: inr,
        ),
        isNull,
      );
      expect(
        buildUpiPaymentUri(
          payeeVpa: 'nonsense',
          payeeName: 'Priya',
          amountMinor: 60000,
          currency: inr,
        ),
        isNull,
      );
    });

    test('refuses a non-positive amount', () {
      expect(
        buildUpiPaymentUri(
          payeeVpa: 'priya@okhdfcbank',
          payeeName: 'Priya',
          amountMinor: 0,
          currency: inr,
        ),
        isNull,
      );
    });
  });
}
