import 'dart:math';

import 'package:opensplit/domain/split/remainder.dart';
import 'package:test/test.dart';

void main() {
  const members = {'alex', 'sam', 'pat'};

  test('starts evenly and reallocates only the automatic rows', () {
    RemainderAllocation allocate(Map<String, int?> overrides) =>
        RemainderAllocation(
          total: 30000,
          memberIds: members,
          overrides: overrides,
        );
    expect(allocate({}).values.values, everyElement(10000));
    expect(allocate({'alex': 12000}).values, {
      'alex': 12000,
      'sam': 9000,
      'pat': 9000,
    });
    expect(allocate({'alex': 12000, 'sam': 8000}).values, {
      'alex': 12000,
      'sam': 8000,
      'pat': 10000,
    });
    expect(allocate({'alex': 0}).values, {
      'alex': 0,
      'sam': 15000,
      'pat': 15000,
    });
  });

  test('ignores excluded overrides without modifying the input', () {
    final overrides = {'alex': 120, 'sam': 80, 'outsider': -50};
    final allocation = RemainderAllocation(
      total: 300,
      memberIds: {'alex', 'pat'},
      overrides: overrides,
    );
    expect(allocation.values, {'alex': 120, 'pat': 180});
    expect(overrides, {'alex': 120, 'sam': 80, 'outsider': -50});
    expect(allocation.isBalanced, isTrue);
    expect(() => allocation.values['pat'] = 0, throwsUnsupportedError);
  });

  test('keeps fixed values when no valid remainder can be allocated', () {
    final tooMuch = RemainderAllocation(
      total: 300,
      memberIds: members,
      overrides: {'alex': 400},
    );
    expect(tooMuch.problem, RemainderProblem.overallocated);
    expect(tooMuch.remaining, -100);
    expect(tooMuch.values, {'alex': 400});
    final invalid = RemainderAllocation(
      total: 300,
      memberIds: members,
      overrides: {'alex': null, 'sam': -10},
    );
    expect(invalid.problem, RemainderProblem.invalidOverrides);
    expect(invalid.invalid, {'alex', 'sam'});
    expect(invalid.values, isEmpty);
  });

  test(
    'all fixed values must add up exactly, and empty membership is invalid',
    () {
      for (final (total, problem) in [
        (300, null),
        (301, RemainderProblem.unallocated),
        (299, RemainderProblem.overallocated),
      ]) {
        final allocation = RemainderAllocation(
          total: total,
          memberIds: members,
          overrides: {'alex': 120, 'sam': 80, 'pat': 100},
        );
        expect(allocation.problem, problem);
        expect(allocation.values, {'alex': 120, 'sam': 80, 'pat': 100});
      }
      expect(
        RemainderAllocation(total: 0, memberIds: {}, overrides: {}).problem,
        RemainderProblem.noMembers,
      );
    },
  );

  test('percentages retain full precision so equal shares stay equal', () {
    final even = RemainderAllocation(
      total: 100000000,
      memberIds: members,
      overrides: {},
    );
    expect(even.values.values.toList()..sort(), [33333333, 33333333, 33333334]);
    final precise = RemainderAllocation(
      total: 100000000,
      memberIds: members,
      overrides: {'alex': 23456789},
    );
    expect(precise.values['alex'], 23456789);
    expect(
      precise.values.values.fold(0, (sum, value) => sum + value),
      100000000,
    );
    expect((precise.values['sam']! - precise.values['pat']!).abs(), 1);
  });

  test('zero and indivisible totals have exact, non-negative allocations', () {
    for (var total = 0; total < 100; total++) {
      final allocation = RemainderAllocation(
        total: total,
        memberIds: members,
        overrides: {},
      );
      expect(
        allocation.values.values.fold(0, (sum, value) => sum + value),
        total,
      );
      expect(allocation.values.values.every((value) => value >= 0), isTrue);
    }
  });

  test('large sums cannot overflow into a valid allocation', () {
    final allocation = RemainderAllocation(
      total: 100,
      memberIds: members,
      overrides: {'alex': 0x7fffffffffffffff, 'sam': 0x7fffffffffffffff},
    );
    expect(allocation.problem, RemainderProblem.overallocated);
  });

  test(
    'random allocations conserve totals, preserve overrides and ignore order',
    () {
      final random = Random(24);
      for (var sample = 0; sample < 1000; sample++) {
        final ids = {for (var i = 0; i < 2 + random.nextInt(12); i++) 'm-$i'};
        final total = random.nextInt(1000000);
        var left = total;
        final overrides = <String, int>{};
        for (final id in ids.take(ids.length - 1)) {
          if (!random.nextBool()) continue;
          final value = random.nextInt(left + 1);
          overrides[id] = value;
          left -= value;
        }
        RemainderAllocation allocate(Set<String> members) =>
            RemainderAllocation(
              total: total,
              memberIds: members,
              overrides: overrides,
              seed: 'expense-$sample',
            );
        final result = allocate(ids);
        expect(result.isBalanced, isTrue);
        expect(result.values.keys.toSet(), ids);
        expect(
          result.values.values.fold(0, (sum, value) => sum + value),
          total,
        );
        for (final entry in overrides.entries) {
          expect(result.values[entry.key], entry.value);
        }
        expect(result.values.values.every((value) => value >= 0), isTrue);
        final automatic = result.automatic
            .map((id) => result.values[id]!)
            .toList();
        expect(
          automatic.reduce(max) - automatic.reduce(min),
          lessThanOrEqualTo(1),
        );
        expect(allocate(ids.toList().reversed.toSet()).values, result.values);
      }
    },
  );
}
