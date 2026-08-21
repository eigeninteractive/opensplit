import 'dart:math';

import 'package:opensplit/domain/split/allocation.dart';
import 'package:test/test.dart';

import 'generators.dart';

void main() {
  group('allocateLargestRemainder', () {
    test('splits 100.00 across three people as 33.34 / 33.33 / 33.33', () {
      final result = allocateLargestRemainder(
        totalMinor: 10000,
        parties: const [
          (memberId: 'a', weightMicros: weightScale),
          (memberId: 'b', weightMicros: weightScale),
          (memberId: 'c', weightMicros: weightScale),
        ],
      );

      expect(result.values.reduce((a, b) => a + b), 10000);
      expect(result.values.toList()..sort(), [3333, 3333, 3334]);
      // The extra paisa goes to the lowest member id, not to whoever happened
      // to be listed first.
      expect(result['a'], 3334);
    });

    test('honours a 2:1:1 weighting', () {
      final result = allocateLargestRemainder(
        totalMinor: 40000,
        parties: const [
          (memberId: 'a', weightMicros: 2 * weightScale),
          (memberId: 'b', weightMicros: weightScale),
          (memberId: 'c', weightMicros: weightScale),
        ],
      );

      expect(result, {'a': 20000, 'b': 10000, 'c': 10000});
    });

    test('gives a zero-weight member nothing', () {
      final result = allocateLargestRemainder(
        totalMinor: 999,
        parties: const [
          (memberId: 'a', weightMicros: weightScale),
          (memberId: 'b', weightMicros: 0),
        ],
      );

      expect(result, {'a': 999, 'b': 0});
    });

    test('iterates in ascending member id order regardless of input order', () {
      final result = allocateLargestRemainder(
        totalMinor: 300,
        parties: const [
          (memberId: 'zoe', weightMicros: weightScale),
          (memberId: 'arun', weightMicros: weightScale),
          (memberId: 'priya', weightMicros: weightScale),
        ],
      );

      expect(result.keys, ['arun', 'priya', 'zoe']);
    });

    test('rejects inputs that cannot produce a valid allocation', () {
      expect(
        () => allocateLargestRemainder(totalMinor: 100, parties: const []),
        throwsArgumentError,
      );
      expect(
        () => allocateLargestRemainder(
          totalMinor: -1,
          parties: const [(memberId: 'a', weightMicros: weightScale)],
        ),
        throwsArgumentError,
      );
      expect(
        () => allocateLargestRemainder(
          totalMinor: 100,
          parties: const [
            (memberId: 'a', weightMicros: weightScale),
            (memberId: 'a', weightMicros: weightScale),
          ],
        ),
        throwsArgumentError,
        reason: 'a member cannot hold two shares of one entry',
      );
      expect(
        () => allocateLargestRemainder(
          totalMinor: 100,
          parties: const [(memberId: 'a', weightMicros: 0)],
        ),
        throwsArgumentError,
        reason: 'nothing to allocate against',
      );
      expect(
        () => allocateLargestRemainder(
          totalMinor: 100,
          parties: const [(memberId: 'a', weightMicros: -1)],
        ),
        throwsArgumentError,
      );
    });
  });

  group('allocateLargestRemainder properties', () {
    const cases = 5000;

    test('always sums to exactly the total', () {
      final gen = EntryGen(20260821);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(1 + gen.random.nextInt(10));
        final parties = weightedParties(gen.random, members);
        final total = gen.nextIntUpTo(1000000000000);

        final result = allocateLargestRemainder(
          totalMinor: total,
          parties: parties,
        );

        expect(
          result.values.fold(0, (a, b) => a + b),
          total,
          reason: 'seed ${gen.seed}, case $i, parties $parties',
        );
      }
    });

    test('is invariant under shuffling of the parties', () {
      final gen = EntryGen(99991);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(9));
        final parties = weightedParties(gen.random, members);
        final total = gen.nextIntUpTo(100000000);

        final first = allocateLargestRemainder(
          totalMinor: total,
          parties: parties,
        );

        for (var attempt = 0; attempt < 3; attempt++) {
          final shuffled = [...parties]..shuffle(gen.random);
          final again = allocateLargestRemainder(
            totalMinor: total,
            parties: shuffled,
          );

          // Not just equal contents — an identical ordered map, so that any
          // consumer iterating the result also sees the same thing.
          expect(
            again.entries.map((e) => '${e.key}=${e.value}').join(','),
            first.entries.map((e) => '${e.key}=${e.value}').join(','),
            reason: 'seed ${gen.seed}, case $i',
          );
        }
      }
    });

    test('spreads equal weights within one minor unit', () {
      final gen = EntryGen(4242);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(1 + gen.random.nextInt(10));
        final total = gen.nextIntUpTo(100000000);

        final result = allocateLargestRemainder(
          totalMinor: total,
          parties: [
            for (final id in members) (memberId: id, weightMicros: weightScale),
          ],
        );

        final values = result.values.toList();
        expect(
          values.reduce(max) - values.reduce(min),
          lessThanOrEqualTo(1),
          reason: 'seed ${gen.seed}, case $i, total $total',
        );
      }
    });

    test('stays exact at amounts that overflow a JavaScript double', () {
      // 10^15 minor units multiplied by a 10^6-scaled weight is 10^21, far past
      // the 2^53 where a web int silently loses precision. This is the case the
      // BigInt intermediate exists for.
      final gen = EntryGen(7);
      for (var i = 0; i < 500; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(8));
        final total = 999999999999000 + gen.nextIntUpTo(999);

        final result = allocateLargestRemainder(
          totalMinor: total,
          parties: weightedParties(gen.random, members),
        );

        expect(result.values.fold(0, (a, b) => a + b), total);
      }
    });
  });
}
