import 'package:opensplit/domain/split/allocation.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import 'generators.dart';

void main() {
  group('EqualSplit', () {
    test('resolves to equal shares carrying weight 1', () {
      final shares = const EqualSplit(['b', 'a']).resolve(1000);

      expect(shares.map((s) => s.memberId), ['a', 'b']);
      expect(shares.every((s) => s.weightMicros == weightScale), isTrue);
      expect(shares.fold(0, (sum, s) => sum + s.amountMinor), 1000);
    });

    test('rejects an empty or duplicated participant list', () {
      expect(
        () => const EqualSplit([]).resolve(100),
        throwsA(isA<SplitException>()),
      );
      expect(
        () => const EqualSplit(['a', 'a']).resolve(100),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('ExactSplit', () {
    test('passes the typed amounts through with no weight', () {
      final shares = const ExactSplit({'a': 700, 'b': 300}).resolve(1000);

      expect(shares, [
        (memberId: 'a', amountMinor: 700, weightMicros: null),
        (memberId: 'b', amountMinor: 300, weightMicros: null),
      ]);
    });

    test('rejects amounts that do not add up to the total', () {
      expect(
        () => const ExactSplit({'a': 700, 'b': 200}).resolve(1000),
        throwsA(
          isA<SplitException>().having(
            (e) => e.message,
            'message',
            contains('add up to 900'),
          ),
        ),
      );
    });

    test('rejects a negative share', () {
      expect(
        () => const ExactSplit({'a': 1100, 'b': -100}).resolve(1000),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('SharesSplit', () {
    test('resolves 2:1:1 and records the original share counts', () {
      final shares = const SharesSplit({'a': 2, 'b': 1, 'c': 1}).resolve(40000);

      expect(shares.map((s) => s.amountMinor), [20000, 10000, 10000]);
      expect(shares.first.weightMicros, 2 * weightScale);
    });

    test('rejects an all-zero weighting', () {
      expect(
        () => const SharesSplit({'a': 0, 'b': 0}).resolve(100),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('PercentSplit', () {
    test('resolves percentages given in micros', () {
      final shares = const PercentSplit({
        'a': 60 * weightScale,
        'b': 40 * weightScale,
      }).resolve(1000);

      expect(shares.map((s) => s.amountMinor), [600, 400]);
    });

    test('allows fractional percentages that total exactly 100', () {
      final shares = const PercentSplit({
        'a': 33333333,
        'b': 33333333,
        'c': 33333334,
      }).resolve(10000);

      expect(shares.fold(0, (sum, s) => sum + s.amountMinor), 10000);
    });

    test('rejects percentages that miss 100 and says by how much', () {
      expect(
        () => const PercentSplit({
          'a': 60 * weightScale,
          'b': 37 * weightScale,
        }).resolve(1000),
        throwsA(
          isA<SplitException>().having(
            (e) => e.message,
            'message',
            contains('97.00%'),
          ),
        ),
      );
    });
  });

  group('resolvePayers', () {
    test('orders payers by member id', () {
      final payers = resolvePayers(
        totalMinor: 1000,
        amountsByMemberId: const {'zoe': 400, 'arun': 600},
      );

      expect(payers, [
        (memberId: 'arun', amountMinor: 600),
        (memberId: 'zoe', amountMinor: 400),
      ]);
    });

    test('rejects payments that do not add up, or are not payments', () {
      expect(
        () => resolvePayers(totalMinor: 1000, amountsByMemberId: const {}),
        throwsA(isA<SplitException>()),
      );
      expect(
        () => resolvePayers(
          totalMinor: 1000,
          amountsByMemberId: const {'a': 900},
        ),
        throwsA(isA<SplitException>()),
      );
      expect(
        () => resolvePayers(
          totalMinor: 1000,
          amountsByMemberId: const {'a': 1000, 'b': 0},
        ),
        throwsA(isA<SplitException>()),
        reason: 'a payer who paid nothing is not a payer',
      );
    });
  });

  group('split properties', () {
    test('every split kind resolves to exactly the entry total', () {
      final gen = EntryGen(31337);
      for (var i = 0; i < 5000; i++) {
        final members = gen.memberIds(1 + gen.random.nextInt(10));
        final total = 1 + gen.nextIntUpTo(1000000000000);
        final spec = gen.splitSpec(members, total);

        final shares = spec.resolve(total);

        expect(
          shares.fold(0, (sum, s) => sum + s.amountMinor),
          total,
          reason: 'seed ${gen.seed}, case $i, kind ${spec.kind}',
        );
        expect(
          shares.map((s) => s.memberId).toList(),
          shares.map((s) => s.memberId).toList()..sort(),
          reason: 'shares must come back ordered by member id',
        );
      }
    });
  });
}
