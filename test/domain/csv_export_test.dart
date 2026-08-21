import 'package:opensplit/domain/export/csv_export.dart';
import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry.dart';
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
  required String description,
  String currency = 'INR',
  int amountMinor = 240000,
  Map<String, int> payers = const {'ravi': 240000},
  Map<String, int> shares = const {'ravi': 120000, 'priya': 120000},
  String? notes,
  String? categoryId,
  DateTime? deletedAt,
}) {
  final at = DateTime.utc(2026, 8, 21);
  return Entry(
    id: 'e1',
    groupId: 'g1',
    kind: EntryKind.expense,
    description: description,
    categoryId: categoryId,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: at,
    splitKind: SplitKind.equal,
    payers: [
      for (final e in payers.entries)
        EntryPayer(memberId: e.key, amountMinor: e.value),
    ],
    shares: [
      for (final e in shares.entries)
        EntryShare(memberId: e.key, amountMinor: e.value),
    ],
    notes: notes,
    createdBy: 'ravi',
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}

const _names = {'ravi': 'Ravi', 'priya': 'Priya'};
const _currencies = {'INR': inr, 'JPY': jpy};

void main() {
  test('writes a header and one row per entry', () {
    final csv = entriesToCsv(
      [_entry(description: 'Dinner')],
      memberNames: _names,
      currencies: _currencies,
    );

    final lines = csv.trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('date,kind,description'));
    expect(lines[1], contains('2026-08-21,expense,Dinner'));
  });

  test('keeps every payer and share, not just the net position', () {
    final csv = entriesToCsv(
      [
        _entry(
          description: 'Groceries',
          payers: {'ravi': 200000, 'priya': 40000},
        ),
      ],
      memberNames: _names,
      currencies: _currencies,
    );

    expect(csv, contains('Ravi: 2000.00; Priya: 400.00'));
    expect(csv, contains('Ravi: 1200.00; Priya: 1200.00'));
  });

  test('formats amounts at the currency own precision', () {
    final csv = entriesToCsv(
      [
        _entry(
          description: 'Ramen',
          currency: 'JPY',
          amountMinor: 2400,
          payers: {'ravi': 2400},
          shares: {'ravi': 2400},
        ),
      ],
      memberNames: _names,
      currencies: _currencies,
    );

    expect(csv, contains(',JPY,2400,'));
    expect(csv, isNot(contains('24.00')));
  });

  test('escapes commas, quotes and newlines', () {
    final csv = entriesToCsv(
      [
        _entry(
          description: 'Dinner, drinks and a "show"',
          notes: 'split\nover two lines',
        ),
      ],
      memberNames: _names,
      currencies: _currencies,
    );

    expect(csv, contains('"Dinner, drinks and a ""show"""'));
    expect(csv, contains('"split\nover two lines"'));
  });

  test('omits deleted entries', () {
    final csv = entriesToCsv(
      [_entry(description: 'Gone', deletedAt: DateTime.utc(2026, 9))],
      memberNames: _names,
      currencies: _currencies,
    );

    expect(csv.trim().split('\n'), hasLength(1), reason: 'header only');
  });

  test('names categories when it knows them', () {
    final csv = entriesToCsv(
      [_entry(description: 'Cab', categoryId: 'c1')],
      memberNames: _names,
      currencies: _currencies,
      categoryNames: const {'c1': 'Transport'},
    );

    expect(csv, contains(',Transport,'));
  });
}
