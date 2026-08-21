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

  group('rounding leftovers rotate', () {
    // Three people, ₹100. Someone has to take the extra paisa.
    List<WeightedParty> trio() => const [
      (memberId: 'aaa', weightMicros: weightScale),
      (memberId: 'bbb', weightMicros: weightScale),
      (memberId: 'ccc', weightMicros: weightScale),
    ];

    String favoured(String? seed) {
      final result = allocateLargestRemainder(
        totalMinor: 10000,
        parties: trio(),
        seed: seed,
      );
      return result.entries.firstWhere((e) => e.value == 3334).key;
    }

    test('the same seed always favours the same member', () {
      expect(favoured('entry-1'), favoured('entry-1'));
      expect(favoured('entry-1'), favoured('entry-1'));
    });

    test('an edit to the same entry reproduces the same split', () {
      // Editing re-runs the allocator with the entry's own id, so the split
      // must not shuffle underneath a correction to the amount or the notes.
      final first = allocateLargestRemainder(
        totalMinor: 10000,
        parties: trio(),
        seed: 'entry-42',
      );
      final second = allocateLargestRemainder(
        totalMinor: 10000,
        parties: trio(),
        seed: 'entry-42',
      );
      expect(first, second);
    });

    test('different entries do not all favour the same member', () {
      // The bug this replaces: with a fixed tiebreak, one member absorbed the
      // extra minor unit on every equal split for the life of the group.
      final seen = {for (var i = 0; i < 60; i++) favoured('entry-$i')};
      expect(
        seen.length,
        greaterThan(1),
        reason: 'a fixed tiebreak would put every leftover on one member',
      );
    });

    test('no seed keeps the old ascending-id behaviour', () {
      expect(favoured(null), 'aaa');
    });

    test('the sum is exact whatever the seed', () {
      for (var i = 0; i < 200; i++) {
        final result = allocateLargestRemainder(
          totalMinor: 10000,
          parties: trio(),
          seed: 'seed-$i',
        );
        expect(result.values.reduce((a, b) => a + b), 10000);
      }
    });

    test('a seed cannot change anyone\'s share by more than one unit', () {
      // Rotation decides who absorbs a leftover, never how much anyone owes.
      for (var i = 0; i < 50; i++) {
        final result = allocateLargestRemainder(
          totalMinor: 10000,
          parties: trio(),
          seed: 'seed-$i',
        );
        for (final amount in result.values) {
          expect(amount, anyOf(3333, 3334));
        }
      }
    });

    test('a seed does not disturb an allocation with no leftover', () {
      // ₹99 over three is exact, so there is nothing to hand out and every
      // seed must produce the identical result.
      for (var i = 0; i < 20; i++) {
        final result = allocateLargestRemainder(
          totalMinor: 9900,
          parties: trio(),
          seed: 'seed-$i',
        );
        expect(result.values, everyElement(3300));
      }
    });

    // Pinned values, run on the VM and in Chrome by CI.
    //
    // This is the test that matters most in this group. The first version of
    // the hash used a plain `hash * prime` masked to 32 bits, which is correct
    // on a 64-bit int and lossy on a JavaScript double — the product reaches
    // 2^56 and the web is exact only to 2^53. The two platforms then chose
    // different members for the same entry, meaning a phone and the web app
    // would split one expense differently and the sync would flip between
    // them. Nothing but pinned cross-platform values catches that.
    test('a seed picks the same member on every platform', () {
      expect(favoured('entry-1'), 'bbb');
      expect(favoured('entry-2'), 'bbb');
      expect(favoured('entry-3'), 'aaa');
      expect(favoured('goa-dinner'), 'ccc');
      expect(favoured('f47ac10b'), 'aaa');
    });

    test('unequal weights still win over the rotation', () {
      // The rotation only breaks ties. A genuinely larger remainder must still
      // take precedence, or the allocation stops being largest-remainder.
      for (var i = 0; i < 30; i++) {
        final result = allocateLargestRemainder(
          totalMinor: 100,
          parties: const [
            (memberId: 'aaa', weightMicros: 1 * weightScale),
            (memberId: 'bbb', weightMicros: 1 * weightScale),
            (memberId: 'ccc', weightMicros: 7 * weightScale),
          ],
          seed: 'seed-$i',
        );
        // 100 * 7/9 = 77.7 -> floor 77, the largest remainder by far.
        expect(result['ccc'], 78);
      }
    });
  });
}
