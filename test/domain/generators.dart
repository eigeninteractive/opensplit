import 'dart:math';

import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/allocation.dart';
import 'package:opensplit/domain/split/splitter.dart';

/// Deterministic random generators for property-based tests.
///
/// Every generator draws from a seeded [Random], so a failure is reproducible
/// from the seed printed in the test name rather than being a one-off that
/// vanishes on re-run. The domain is pure functions over immutable data, which
/// is what makes generating thousands of cases cheap: no database, no network,
/// milliseconds per thousand.
class EntryGen {
  EntryGen(this.seed) : random = Random(seed);

  final int seed;
  final Random random;

  static const List<String> currencies = ['INR', 'USD', 'JPY', 'KWD'];

  /// Member ids are deliberately not sorted-looking, and are of mixed length,
  /// so that any accidental dependence on insertion order or id shape shows up.
  List<String> memberIds(int count) => [
    for (var i = 0; i < count; i++) 'm${_pad(random.nextInt(1 << 30))}-$i',
  ];

  static String _pad(int n) => n.toString().padLeft(10, '0');

  /// A random non-negative integer in `[0, maxInclusive]`.
  ///
  /// `Random.nextInt` caps at 2^32, so larger bounds are composed from two
  /// draws — needed to exercise amounts big enough to overflow a JavaScript
  /// double when multiplied by a 10^6-scaled weight.
  int nextIntUpTo(int maxInclusive) {
    if (maxInclusive <= 0) return 0;
    if (maxInclusive < 0xFFFFFFFF) return random.nextInt(maxInclusive + 1);
    final high = random.nextInt(1 << 21);
    final low = random.nextInt(1 << 31);
    return ((high << 31) | low) % (maxInclusive + 1);
  }

  /// Splits [total] into exactly [parts] non-negative integers summing to
  /// [total], by picking cut points on the interval.
  ///
  /// With [allowZero] false every part is at least 1, which requires
  /// `total >= parts`.
  List<int> partition(int total, int parts, {bool allowZero = true}) {
    if (parts <= 1) return [total];

    final List<int> cuts;
    if (allowZero) {
      cuts = [for (var i = 0; i < parts - 1; i++) nextIntUpTo(total)]..sort();
    } else {
      if (total < parts) {
        throw ArgumentError('cannot split $total into $parts positive parts');
      }
      final distinct = <int>{};
      while (distinct.length < parts - 1) {
        distinct.add(1 + nextIntUpTo(total - 2));
      }
      cuts = distinct.toList()..sort();
    }

    final result = <int>[];
    var previous = 0;
    for (final cut in cuts) {
      result.add(cut - previous);
      previous = cut;
    }
    result.add(total - previous);
    return result;
  }

  /// A random split specification over a random non-empty subset of [members].
  SplitSpec splitSpec(List<String> members, int totalMinor) {
    final participants = subset(members, minSize: 1);
    final kind = SplitKind.values[random.nextInt(SplitKind.values.length)];

    switch (kind) {
      case SplitKind.equal:
        return EqualSplit(participants);

      case SplitKind.exact:
        final amounts = partition(totalMinor, participants.length);
        return ExactSplit({
          for (var i = 0; i < participants.length; i++)
            participants[i]: amounts[i],
        });

      case SplitKind.shares:
        return SharesSplit({
          for (final id in participants) id: 1 + random.nextInt(5),
        });

      case SplitKind.percent:
        final micros = partition(
          PercentSplit.fullPercentMicros,
          participants.length,
        );
        return PercentSplit({
          for (var i = 0; i < participants.length; i++)
            participants[i]: micros[i],
        });
    }
  }

  /// A random non-empty subset of [items], in shuffled order.
  List<String> subset(List<String> items, {int minSize = 1}) {
    final shuffled = [...items]..shuffle(random);
    final size = minSize + random.nextInt(items.length - minSize + 1);
    return shuffled.take(size).toList();
  }

  /// A random expense over [members], guaranteed to satisfy the invariant.
  ///
  /// Amounts reach 10^12 minor units so that the allocation's [BigInt]
  /// intermediates are genuinely exercised rather than staying comfortably
  /// inside double precision.
  Entry expense(List<String> members, {required int index}) {
    final currency = currencies[random.nextInt(currencies.length)];
    final total = 1 + nextIntUpTo(1000000000000);

    final spec = splitSpec(members, total);
    final shares = spec.resolve(total);

    final payerIds = subset(members);
    final payerCount = min(payerIds.length, total);
    final payerAmounts = partition(total, payerCount, allowZero: false);
    final payers = {
      for (var i = 0; i < payerCount; i++) payerIds[i]: payerAmounts[i],
    };
    final resolvedPayers = resolvePayers(
      totalMinor: total,
      amountsByMemberId: payers,
    );

    final createdAt = DateTime.utc(2026, 1, 1).add(Duration(minutes: index));
    return Entry(
      id: 'e${_pad(index)}',
      groupId: 'g1',
      kind: EntryKind.expense,
      description: 'expense $index',
      currency: currency,
      amountMinor: total,
      entryDate: DateTime.utc(2026, 1, 1 + (index % 28)),
      splitKind: spec.kind,
      payers: [
        for (final p in resolvedPayers)
          EntryPayer(memberId: p.memberId, amountMinor: p.amountMinor),
      ],
      shares: [
        for (final s in shares)
          EntryShare(
            memberId: s.memberId,
            amountMinor: s.amountMinor,
            weightMicros: s.weightMicros,
          ),
      ],
      createdBy: members.first,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  /// A group's worth of random expenses, some of them soft-deleted.
  List<Entry> entries(List<String> members, int count) => [
    for (var i = 0; i < count; i++)
      if (random.nextInt(10) == 0)
        expense(members, index: i).copyWith(deletedAt: DateTime.utc(2026, 2, 1))
      else
        expense(members, index: i),
  ];
}

/// A weight list for allocation tests.
List<WeightedParty> weightedParties(Random random, List<String> members) => [
  for (final id in members)
    (memberId: id, weightMicros: 1 + random.nextInt(10 * weightScale)),
];
