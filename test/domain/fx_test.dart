import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/domain/fx/convert.dart';
import 'package:opensplit/domain/fx/estimated_total.dart';
import 'package:opensplit/domain/fx/fx_quote.dart';
import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';

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

/// One entry, seen from `me`'s side: what they paid and what they owe.
Entry entry({
  required String currency,
  required int paid,
  required int share,
  double? fxRate,
  bool deleted = false,
  String member = 'me',
}) {
  final date = DateTime.utc(2026, 8, 20);
  return Entry(
    id: 'e-$currency-$paid-$share-$member',
    groupId: 'g',
    kind: EntryKind.expense,
    description: 'test',
    currency: currency,
    amountMinor: paid,
    entryDate: date,
    splitKind: SplitKind.equal,
    payers: [if (paid != 0) EntryPayer(memberId: member, amountMinor: paid)],
    shares: [if (share != 0) EntryShare(memberId: member, amountMinor: share)],
    fxRate: fxRate,
    createdBy: member,
    createdAt: date,
    updatedAt: date,
    deletedAt: deleted ? date : null,
  );
}

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

  group('estimateBalance', () {
    const currencies = {'INR': inr, 'USD': usd, 'JPY': jpy};

    test('converts each entry at the rate stamped on that entry', () {
      // The same currency on two days at two rates. Folding the currency first
      // and converting once could only ever use one of them.
      final total = estimateBalance(
        entries: [
          entry(currency: 'USD', paid: 1000, share: 0, fxRate: 80),
          entry(currency: 'USD', paid: 1000, share: 0, fxRate: 90),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, 80000 + 90000);
      expect(total.isComplete, isTrue);
    });

    test('adds up to the per-expense figures shown above it', () {
      // The property the whole change exists for: the estimate is the sum of
      // the numbers on screen, not an independently derived one.
      final entries = [
        entry(currency: 'USD', paid: 2500, share: 1250, fxRate: 87.5),
        entry(currency: 'JPY', paid: 5000, share: 2500, fxRate: 0.56),
        entry(currency: 'INR', paid: 100000, share: 50000),
      ];
      final perEntry = [
        convertMinor(amountMinor: 1250, from: usd, to: inr, rate: 87.5),
        convertMinor(amountMinor: 2500, from: jpy, to: inr, rate: 0.56),
        50000,
      ];

      final total = estimateBalance(
        entries: entries,
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, perEntry.reduce((a, b) => a + b));
    });

    test('rounds per entry, which is what makes the sum reconcile', () {
      // 0.01 USD at 87.5 is 0.875 INR, which rounds up to 88 paise. Two of
      // them shown on screen read 88 + 88 = 176. Converting the 0.02 USD
      // total instead gives 1.75 INR -> 175. The old behaviour produced 175
      // and printed 176, and this is the one paisa that told the user the
      // screen did not add up.
      final total = estimateBalance(
        entries: [
          entry(currency: 'USD', paid: 1, share: 0, fxRate: 87.5),
          entry(currency: 'USD', paid: 1, share: 0, fxRate: 87.5),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, 176);
      expect(
        convertMinor(amountMinor: 2, from: usd, to: inr, rate: 87.5),
        175,
        reason: 'converting the currency total is the number we are not using',
      );
    });

    test('a settlement folds through the same path as an expense', () {
      final total = estimateBalance(
        entries: [
          entry(currency: 'USD', paid: 1000, share: 0, fxRate: 80),
          entry(currency: 'USD', paid: 0, share: 1000, fxRate: 80),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      // Paid then repaid: nothing owed, and the estimate says so rather than
      // returning null.
      expect(total!.amountMinor, 0);
    });

    test('names a currency whose entry carries no rate', () {
      final total = estimateBalance(
        entries: [
          entry(currency: 'INR', paid: 100000, share: 0),
          entry(currency: 'USD', paid: 1000, share: 0),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, 100000);
      expect(total.isComplete, isFalse);
      expect(total.unconverted, ['USD']);
    });

    test('skips soft-deleted entries, as the balance fold does', () {
      final total = estimateBalance(
        entries: [
          entry(currency: 'INR', paid: 100000, share: 0),
          entry(
            currency: 'USD',
            paid: 1000,
            share: 0,
            fxRate: 80,
            deleted: true,
          ),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, 100000);
      expect(total.isComplete, isTrue);
    });

    test('ignores entries this member had no part in', () {
      final total = estimateBalance(
        entries: [
          entry(currency: 'INR', paid: 100000, share: 0),
          entry(currency: 'USD', paid: 0, share: 0, member: 'someone-else'),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.amountMinor, 100000);
      expect(
        total.isComplete,
        isTrue,
        reason: 'an entry that does not touch you cannot be uncovertible',
      );
    });

    test('returns null when nothing could be converted at all', () {
      // Distinct from an estimate of zero: the screen must say nothing rather
      // than claim the user is settled.
      final total = estimateBalance(
        entries: [entry(currency: 'USD', paid: 1000, share: 0)],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total, isNull);
    });

    test('refuses a non-positive stored rate rather than trusting it', () {
      final total = estimateBalance(
        entries: [
          entry(currency: 'INR', paid: 100000, share: 0),
          entry(currency: 'USD', paid: 1000, share: 0, fxRate: 0),
        ],
        memberId: 'me',
        target: 'INR',
        currencies: currencies,
      );
      expect(total!.unconverted, ['USD']);
    });
  });
}
