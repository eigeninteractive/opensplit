import 'package:opensplit/data/local/database.dart' show EntryRow;
import 'package:opensplit/domain/analytics/spending.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit_api/opensplit_api.dart'
    show EntryKind, Payer, Share, SplitKind;
import 'package:test/test.dart';

Entry _entry(
  String id, {
  required DateTime day,
  required Map<String, int> paid,
  required Map<String, int> shares,
  String currency = 'INR',
  String? category,
  EntryKind kind = EntryKind.expense,
  DateTime? deletedAt,
}) => Entry(
  EntryRow(
    id: id,
    groupId: 'g',
    kind: kind,
    description: id,
    currency: currency,
    amountMinor: paid.values.fold(0, (a, b) => a + b),
    entryDate: day,
    categoryId: category,
    splitKind: SplitKind.exact,
    createdBy: paid.keys.first,
    createdAt: day,
    deletedAt: deletedAt,
  ),
  payers: [
    for (final MapEntry(:key, :value) in paid.entries)
      Payer(memberId: key, amountMinor: value),
  ],
  shares: [
    for (final MapEntry(:key, :value) in shares.entries)
      Share(memberId: key, amountMinor: value, weightMicros: null),
  ],
);

DateTime _day(int month, int day) => DateTime.utc(2026, month, day);

void main() {
  final entries = [
    _entry(
      'hotel',
      day: _day(11, 3),
      paid: {'ana': 9000},
      shares: {'ana': 3000, 'bo': 3000, 'cy': 3000},
      category: 'stay',
    ),
    _entry(
      'dinner',
      day: _day(11, 5),
      paid: {'bo': 1200},
      shares: {'bo': 600, 'cy': 600},
      category: 'food',
    ),
    _entry(
      'lunch',
      day: _day(11, 5),
      paid: {'ana': 300},
      shares: {'ana': 100, 'bo': 200},
      category: 'food',
    ),
    _entry(
      'refund',
      day: _day(11, 5),
      kind: EntryKind.settlement,
      paid: {'bo': 500},
      shares: {'ana': 500},
    ),
    _entry(
      'deleted',
      day: _day(11, 5),
      paid: {'ana': 700},
      shares: {'ana': 700},
      deletedAt: _day(11, 6),
    ),
    _entry(
      'euros',
      day: _day(11, 5),
      currency: 'EUR',
      paid: {'ana': 50},
      shares: {'ana': 50},
    ),
  ];

  test('counts whole bills in one currency, never payments or deletions', () {
    final summary = SpendingSummary.of(entries, currency: 'INR');

    expect(summary.totalMinor, 10500);
    expect(summary.expenses.map((e) => e.entry.id), [
      'hotel',
      'dinner',
      'lunch',
    ]);
    expect(summary.paidMinor, isNull);
  });

  test('puts the largest category first', () {
    final summary = SpendingSummary.of(entries, currency: 'INR');

    expect(
      [
        for (final c in summary.byCategory)
          (c.key, c.amountMinor, c.entryCount),
      ],
      [('stay', 9000, 1), ('food', 1500, 2)],
    );
  });

  test('sets what each person paid beside what they used', () {
    final summary = SpendingSummary.of(entries, currency: 'INR');

    expect(
      {
        for (final p in summary.byPerson)
          p.memberId: (p.paidMinor, p.shareMinor),
      },
      {'ana': (9300, 3100), 'bo': (1200, 3800), 'cy': (0, 3600)},
    );
    expect(summary.byPerson.first.memberId, 'bo');
  });

  test('counts one person by their shares, leaving out what they sat out', () {
    final summary = SpendingSummary.of(
      entries,
      currency: 'INR',
      memberId: 'ana',
    );

    expect(summary.totalMinor, 3100);
    expect(summary.paidMinor, 9300);
    expect(summary.expenses.map((e) => (e.entry.id, e.amountMinor)), [
      ('hotel', 3000),
      ('lunch', 100),
    ]);
    expect(summary.byCategory.map((c) => (c.key, c.amountMinor)), [
      ('stay', 3000),
      ('food', 100),
    ]);
  });

  test('keeps to the days asked for, inclusive', () {
    final summary = SpendingSummary.of(
      entries,
      currency: 'INR',
      from: _day(11, 4),
      to: _day(11, 5),
    );

    expect(summary.totalMinor, 1500);
    expect(summary.span, (first: _day(11, 5), last: _day(11, 5)));
  });

  test('charts a short stretch by day and keeps its empty days', () {
    final summary = SpendingSummary.of(entries, currency: 'INR');

    expect(summary.interval, SpendingInterval.day);
    expect(summary.overTime.map((s) => (s.key, s.amountMinor)), [
      (_day(11, 3), 9000),
      (_day(11, 4), 0),
      (_day(11, 5), 1500),
    ]);
    expect(summary.expensesIn(_day(11, 5)).map((e) => e.entry.id), [
      'dinner',
      'lunch',
    ]);
  });

  test('charts a season by weeks starting on Monday, a year by months', () {
    Entry on(DateTime day) =>
        _entry('$day', day: day, paid: {'ana': 100}, shares: {'ana': 100});

    final season = SpendingSummary.of([
      on(_day(9, 2)),
      on(_day(10, 14)),
    ], currency: 'INR');
    expect(season.interval, SpendingInterval.week);
    expect(season.overTime.first.key, _day(8, 31));
    expect(season.overTime, hasLength(7));

    final year = SpendingSummary.of([
      on(_day(1, 20)),
      on(_day(6, 2)),
    ], currency: 'INR');
    expect(year.interval, SpendingInterval.month);
    expect(year.overTime.map((s) => s.key.month), [1, 2, 3, 4, 5, 6]);
  });

  test('has nothing to say about a group that spent nothing', () {
    final summary = SpendingSummary.of(const [], currency: 'INR');

    expect(summary.totalMinor, 0);
    expect(summary.overTime, isEmpty);
    expect(summary.span, isNull);
  });
}
