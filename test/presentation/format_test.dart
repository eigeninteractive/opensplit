import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/presentation/format.dart';
import 'package:test/test.dart';

const inr = Currency(
  code: 'INR',
  exponent: 2,
  symbol: '₹',
  name: 'Indian Rupee',
);
const usd = Currency(code: 'USD', exponent: 2, symbol: r'$', name: 'US Dollar');
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
const xxx = Currency(code: 'XXX', exponent: 2, name: 'No Symbol');

void main() {
  test('groups Indian currencies in lakhs and crores', () {
    expect(formatMoney(inr, 240000), '₹2,400.00');
    expect(formatMoney(inr, 1234567890), '₹1,23,45,678.90');
    expect(formatMoney(inr, 100000), '₹1,000.00');
  });

  test('groups other currencies in thousands', () {
    expect(formatMoney(usd, 1234567890), r'$12,345,678.90');
  });

  test('respects the exponent', () {
    expect(formatMoney(jpy, 250000), '¥250,000');
    expect(formatMoney(kwd, 250000), 'د.ك250.000');
  });

  test('falls back to the code when there is no symbol', () {
    expect(formatMoney(xxx, 100), 'XXX 1.00');
  });

  test('handles signs', () {
    expect(formatMoney(inr, -240000), '-₹2,400.00');
    expect(formatMoney(inr, 240000, alwaysSigned: true), '+₹2,400.00');
    expect(formatMoneyAbs(inr, -240000), '₹2,400.00');
  });

  test('shows raw minor units rather than a wrong figure when unknown', () {
    expect(formatMoney(null, 240000), '240000');
  });

  test('handles small and zero amounts', () {
    expect(formatMoney(inr, 0), '₹0.00');
    expect(formatMoney(inr, 5), '₹0.05');
    expect(formatMoney(jpy, 0), '¥0');
  });
}
