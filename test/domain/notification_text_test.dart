import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/notification_text.dart';
import 'package:opensplit/domain/split/splitter.dart';
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

Entry _entry({
  String description = 'Dinner at Toit',
  EntryKind kind = EntryKind.expense,
  int amountMinor = 240000,
  String currency = 'INR',
}) {
  final at = DateTime.utc(2026, 8, 21);
  return Entry(
    id: 'e1',
    groupId: 'g1',
    kind: kind,
    description: description,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: at,
    splitKind: SplitKind.equal,
    payers: const [EntryPayer(memberId: 'ravi', amountMinor: 240000)],
    shares: const [
      EntryShare(memberId: 'ravi', amountMinor: 120000),
      EntryShare(memberId: 'priya', amountMinor: 120000),
    ],
    createdBy: 'ravi',
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  test('names the expense, the total, and your share', () {
    final text = describeEntry(
      entry: _entry(),
      groupName: 'Flat 4B',
      authorName: 'Ravi',
      currency: inr,
      shareMinor: 60000,
    );

    expect(text.title, 'Flat 4B');
    expect(
      text.body,
      'Ravi added Dinner at Toit — ₹2,400.00. Your share: ₹600.00.',
    );
  });

  test('uses the currency exponent, not a hardcoded two places', () {
    final text = describeEntry(
      entry: _entry(currency: 'JPY', amountMinor: 2400),
      groupName: 'Tokyo',
      authorName: 'Ravi',
      currency: jpy,
      shareMinor: 1200,
    );

    // Grouped, but with no decimal places at all — JPY's exponent is 0.
    expect(text.body, contains('¥2,400'));
    expect(text.body, contains('¥1,200'));
    expect(text.body, isNot(contains('24.00')));
  });

  test('omits the share when there is none, rather than claiming zero', () {
    final text = describeEntry(
      entry: _entry(),
      groupName: 'Flat 4B',
      authorName: 'Ravi',
      currency: inr,
      shareMinor: 0,
    );

    expect(text.body, isNot(contains('Your share')));
    expect(text.body, contains('Ravi added Dinner at Toit'));
  });

  test('falls back gracefully when an expense has no description', () {
    final text = describeEntry(
      entry: _entry(description: '   '),
      groupName: 'Flat 4B',
      authorName: 'Ravi',
      currency: inr,
      shareMinor: 60000,
    );

    expect(text.body, startsWith('Ravi added an expense —'));
  });

  test('describes a settlement as a payment, not a purchase', () {
    final text = describeEntry(
      entry: _entry(kind: EntryKind.settlement, amountMinor: 60000),
      groupName: 'Flat 4B',
      authorName: 'Priya',
      currency: inr,
      shareMinor: 0,
    );

    expect(text.body, contains('recorded paying ₹600.00'));
    expect(text.body, isNot(contains('added')));
  });

  test('can be given the app own formatter, so both agree exactly', () {
    final text = describeEntry(
      entry: _entry(),
      groupName: 'Flat 4B',
      authorName: 'Ravi',
      currency: inr,
      shareMinor: 60000,
      format: (minor) => 'INR $minor',
    );

    expect(text.body, contains('INR 240000'));
  });
}
