import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
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
      actorName: 'Ravi',
      kind: EntryEventKind.created,
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
      actorName: 'Ravi',
      kind: EntryEventKind.created,
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
      actorName: 'Ravi',
      kind: EntryEventKind.created,
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
      actorName: 'Ravi',
      kind: EntryEventKind.created,
      currency: inr,
      shareMinor: 60000,
    );

    expect(text.body, startsWith('Ravi added an expense —'));
  });

  test('describes a settlement as a payment, not a purchase', () {
    final text = describeEntry(
      entry: _entry(kind: EntryKind.settlement, amountMinor: 60000),
      groupName: 'Flat 4B',
      actorName: 'Priya',
      kind: EntryEventKind.created,
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
      actorName: 'Ravi',
      kind: EntryEventKind.created,
      currency: inr,
      shareMinor: 60000,
      format: (minor) => 'INR $minor',
    );

    expect(text.body, contains('INR 240000'));
  });

  // ------------------------------------------------------------------------
  // Every kind, because notifications now fire for every recorded change
  // ------------------------------------------------------------------------
  test('an edit says so, and quotes the new total', () {
    final text = describeEntry(
      entry: _entry(amountMinor: 200000),
      groupName: 'Flat 4B',
      actorName: 'Priya',
      kind: EntryEventKind.edited,
      currency: inr,
      shareMinor: 100000,
    );

    // The message that matters: somebody else changed an expense of yours.
    // Before this fired at all, a correction moved your balance in silence.
    expect(
      text.body,
      'Priya edited Dinner at Toit — now ₹2,000.00. Your share: ₹1,000.00.',
    );
  });

  test('a deletion quotes no share, since there is nothing left to owe', () {
    final text = describeEntry(
      entry: _entry(),
      groupName: 'Flat 4B',
      actorName: 'Priya',
      kind: EntryEventKind.deleted,
      currency: inr,
      shareMinor: 60000,
    );

    expect(text.body, 'Priya deleted Dinner at Toit — ₹2,400.00.');
    expect(
      text.body,
      isNot(contains('Your share')),
      reason:
          'quoting what you owed for an expense that is gone reads as a '
          'charge',
    );
  });

  test('a restore says so rather than reading as a new expense', () {
    final text = describeEntry(
      entry: _entry(),
      groupName: 'Flat 4B',
      actorName: 'Priya',
      kind: EntryEventKind.restored,
      currency: inr,
      shareMinor: 60000,
    );

    expect(text.body, startsWith('Priya restored Dinner at Toit'));
  });

  test('a settlement has its own sentence for every kind', () {
    // Exhaustive by construction: describeEntry switches on the enum, so a
    // new kind without wording fails to compile.
    for (final kind in EntryEventKind.values) {
      final text = describeEntry(
        entry: _entry(kind: EntryKind.settlement, amountMinor: 60000),
        groupName: 'Flat 4B',
        actorName: 'Priya',
        kind: kind,
        currency: inr,
        shareMinor: 0,
      );
      expect(text.body, contains('₹600.00'));
      expect(text.body, isNot(contains('added')));
    }
  });
}
