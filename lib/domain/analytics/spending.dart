/// What a group spent, worked out from its expenses.
library;

import '../models/entry.dart';

/// How finely [SpendingSummary.overTime] is cut.
enum SpendingInterval { day, week, month }

/// One slice of spending: a category, or a stretch of time.
class SpendingSlice<K> {
  const SpendingSlice({
    required this.key,
    required this.amountMinor,
    required this.entryCount,
  });

  final K key;
  final int amountMinor;
  final int entryCount;
}

/// What one person put in and what they used up.
class PersonSpending {
  const PersonSpending({
    required this.memberId,
    required this.paidMinor,
    required this.shareMinor,
  });

  final String memberId;

  /// What they handed over at the till.
  final int paidMinor;

  /// What they consumed: the sum of their shares.
  final int shareMinor;
}

/// An expense and how much of it a summary counts.
typedef CountedExpense = ({Entry entry, int amountMinor});

/// Spending in one currency over a stretch of days.
///
/// With a [memberId] every amount is that person's share and expenses they
/// had no part in are left out, so the figures answer "what did this cost
/// me". Without one they are whole bills.
class SpendingSummary {
  SpendingSummary._({
    required this.currency,
    required this.memberId,
    required this.expenses,
    required this.totalMinor,
    required this.paidMinor,
    required this.byCategory,
    required this.byPerson,
    required this.interval,
    required this.overTime,
  });

  /// Sums [entries], keeping expenses in [currency] dated from [from] to
  /// [to] inclusive. Payments and deleted expenses never count.
  factory SpendingSummary.of(
    Iterable<Entry> entries, {
    required String currency,
    String? memberId,
    DateTime? from,
    DateTime? to,
  }) {
    final expenses = <CountedExpense>[];
    final categories = <String, (int, int)>{};
    final paid = <String, int>{};
    final shares = <String, int>{};

    for (final entry in entries) {
      final day = entry.row.entryDate;
      if (!entry.isSpend || entry.row.currency != currency) continue;
      if (from != null && day.isBefore(from)) continue;
      if (to != null && day.isAfter(to)) continue;

      for (final payer in entry.payers) {
        paid[payer.memberId] = (paid[payer.memberId] ?? 0) + payer.amountMinor;
      }
      for (final share in entry.shares) {
        shares[share.memberId] =
            (shares[share.memberId] ?? 0) + share.amountMinor;
      }

      final amount = memberId == null
          ? entry.row.amountMinor
          : entry.shares
                .where((share) => share.memberId == memberId)
                .fold(0, (sum, share) => sum + share.amountMinor);
      if (amount == 0) continue;

      expenses.add((entry: entry, amountMinor: amount));
      final (sum, count) = categories[entry.row.categoryId ?? ''] ?? (0, 0);
      categories[entry.row.categoryId ?? ''] = (sum + amount, count + 1);
    }

    final interval = _intervalFor(expenses);
    return SpendingSummary._(
      currency: currency,
      memberId: memberId,
      expenses: expenses,
      totalMinor: expenses.fold(0, (sum, e) => sum + e.amountMinor),
      paidMinor: memberId == null ? null : paid[memberId] ?? 0,
      byCategory: [
        for (final MapEntry(:key, value: (sum, count)) in categories.entries)
          SpendingSlice(key: key, amountMinor: sum, entryCount: count),
      ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor)),
      byPerson: [
        for (final id in {...paid.keys, ...shares.keys})
          PersonSpending(
            memberId: id,
            paidMinor: paid[id] ?? 0,
            shareMinor: shares[id] ?? 0,
          ),
      ]..sort((a, b) => b.shareMinor.compareTo(a.shareMinor)),
      interval: interval,
      overTime: _overTime(expenses, interval),
    );
  }

  final String currency;

  /// Whose share is being counted, or null for whole bills.
  final String? memberId;

  /// Every expense counted, in the order the ledger gave them.
  final List<CountedExpense> expenses;

  final int totalMinor;

  /// What [memberId] paid towards the group's bills over the same days, or
  /// null when nobody in particular is being counted.
  final int? paidMinor;

  /// Largest first. The key is a category id, or empty for none.
  final List<SpendingSlice<String>> byCategory;

  /// Everyone who paid or owed anything, biggest spender first. Always whole
  /// bills, whoever [memberId] is.
  final List<PersonSpending> byPerson;

  final SpendingInterval interval;

  /// Oldest first, with the empty stretches in between kept so that a gap
  /// reads as a gap. Each key is the first day of its stretch.
  final List<SpendingSlice<DateTime>> overTime;

  /// The first and last day anything was spent, or null when nothing was.
  ({DateTime first, DateTime last})? get span {
    if (expenses.isEmpty) return null;
    final days = [for (final e in expenses) e.entry.row.entryDate]..sort();
    return (first: days.first, last: days.last);
  }

  /// The expenses in one slice of [overTime].
  Iterable<CountedExpense> expensesIn(DateTime start) =>
      expenses.where((e) => _startOf(e.entry.row.entryDate, interval) == start);
}

/// Days for a fortnight, weeks for a season, months beyond that: whichever
/// gives a chart a readable number of bars.
SpendingInterval _intervalFor(List<CountedExpense> expenses) {
  if (expenses.isEmpty) return SpendingInterval.day;
  final days = expenses.map((e) => e.entry.row.entryDate).toList()..sort();
  final length = days.last.difference(days.first).inDays + 1;
  if (length <= 14) return SpendingInterval.day;
  if (length <= 98) return SpendingInterval.week;
  return SpendingInterval.month;
}

/// The first day of the stretch [day] falls in. Weeks start on Monday.
DateTime _startOf(DateTime day, SpendingInterval interval) =>
    switch (interval) {
      SpendingInterval.day => DateTime.utc(day.year, day.month, day.day),
      SpendingInterval.week => DateTime.utc(
        day.year,
        day.month,
        day.day - (day.weekday - DateTime.monday),
      ),
      SpendingInterval.month => DateTime.utc(day.year, day.month),
    };

DateTime _next(DateTime start, SpendingInterval interval) => switch (interval) {
  SpendingInterval.day => DateTime.utc(start.year, start.month, start.day + 1),
  SpendingInterval.week => DateTime.utc(start.year, start.month, start.day + 7),
  SpendingInterval.month => DateTime.utc(start.year, start.month + 1),
};

List<SpendingSlice<DateTime>> _overTime(
  List<CountedExpense> expenses,
  SpendingInterval interval,
) {
  if (expenses.isEmpty) return const [];
  final sums = <DateTime, (int, int)>{};
  for (final expense in expenses) {
    final start = _startOf(expense.entry.row.entryDate, interval);
    final (sum, count) = sums[start] ?? (0, 0);
    sums[start] = (sum + expense.amountMinor, count + 1);
  }
  final starts = sums.keys.toList()..sort();
  return [
    for (
      var start = starts.first;
      !start.isAfter(starts.last);
      start = _next(start, interval)
    )
      SpendingSlice(
        key: start,
        amountMinor: sums[start]?.$1 ?? 0,
        entryCount: sums[start]?.$2 ?? 0,
      ),
  ];
}
