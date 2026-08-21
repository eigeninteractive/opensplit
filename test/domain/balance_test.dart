import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/balance/member_balance.dart';
import 'package:opensplit/domain/balance/simplify.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import 'generators.dart';

Entry _entry({
  required String id,
  required String currency,
  required int amountMinor,
  required Map<String, int> payers,
  required Map<String, int> shares,
  EntryKind kind = EntryKind.expense,
  DateTime? deletedAt,
}) {
  final at = DateTime.utc(2026, 1, 1);
  return Entry(
    id: id,
    groupId: 'g1',
    kind: kind,
    description: id,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: at,
    splitKind: SplitKind.exact,
    payers: [
      for (final e in payers.entries)
        EntryPayer(memberId: e.key, amountMinor: e.value),
    ],
    shares: [
      for (final e in shares.entries)
        EntryShare(memberId: e.key, amountMinor: e.value),
    ],
    createdBy: payers.keys.first,
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}

/// Settles a transfer the way the app does: an entry whose single payer is the
/// debtor and whose single share is the creditor.
Entry _settlement(Transfer transfer, int index) => _entry(
  id: 's$index',
  kind: EntryKind.settlement,
  currency: transfer.currency,
  amountMinor: transfer.amountMinor,
  payers: {transfer.fromMemberId: transfer.amountMinor},
  shares: {transfer.toMemberId: transfer.amountMinor},
);

void main() {
  group('foldBalances', () {
    test('credits the payer and debits each share', () {
      final balances = foldBalances([
        _entry(
          id: 'e1',
          currency: 'INR',
          amountMinor: 2400,
          payers: {'ravi': 2400},
          shares: {'ravi': 800, 'priya': 800, 'arun': 800},
        ),
      ]);

      expect(balances, [
        const MemberBalance(
          memberId: 'arun',
          currency: 'INR',
          balanceMinor: -800,
        ),
        const MemberBalance(
          memberId: 'priya',
          currency: 'INR',
          balanceMinor: -800,
        ),
        const MemberBalance(
          memberId: 'ravi',
          currency: 'INR',
          balanceMinor: 1600,
        ),
      ]);
    });

    test('omits members who net to zero', () {
      final balances = foldBalances([
        _entry(
          id: 'e1',
          currency: 'INR',
          amountMinor: 1000,
          payers: {'a': 1000},
          shares: {'a': 1000},
        ),
      ]);

      expect(balances, isEmpty);
    });

    test('ignores soft-deleted entries', () {
      final balances = foldBalances([
        _entry(
          id: 'e1',
          currency: 'INR',
          amountMinor: 1000,
          payers: {'a': 1000},
          shares: {'b': 1000},
          deletedAt: DateTime.utc(2026, 2, 1),
        ),
      ]);

      expect(balances, isEmpty);
    });

    test('keeps currencies apart rather than netting them', () {
      final balances = foldBalances([
        _entry(
          id: 'e1',
          currency: 'INR',
          amountMinor: 50000,
          payers: {'a': 50000},
          shares: {'b': 50000},
        ),
        _entry(
          id: 'e2',
          currency: 'EUR',
          amountMinor: 2000,
          payers: {'b': 2000},
          shares: {'a': 2000},
        ),
      ]);

      expect(balances, hasLength(4));
      expect(balancesByCurrency(balances).keys, ['EUR', 'INR']);
    });

    test('a settlement folds through the same path and clears the debt', () {
      final expense = _entry(
        id: 'e1',
        currency: 'INR',
        amountMinor: 1200,
        payers: {'ravi': 1200},
        shares: {'ravi': 600, 'priya': 600},
      );
      final settlement = _entry(
        id: 's1',
        kind: EntryKind.settlement,
        currency: 'INR',
        amountMinor: 600,
        payers: {'priya': 600},
        shares: {'ravi': 600},
      );

      expect(foldBalances([expense]), hasLength(2));
      expect(foldBalances([expense, settlement]), isEmpty);
    });
  });

  group('simplifyDebts', () {
    test('routes one debtor to one creditor', () {
      final transfers = simplifyDebts(const [
        MemberBalance(memberId: 'a', currency: 'INR', balanceMinor: 600),
        MemberBalance(memberId: 'b', currency: 'INR', balanceMinor: -600),
      ]);

      expect(transfers, [
        const Transfer(
          fromMemberId: 'b',
          toMemberId: 'a',
          currency: 'INR',
          amountMinor: 600,
        ),
      ]);
    });

    test('settles n members in at most n-1 payments', () {
      final transfers = simplifyDebts(const [
        MemberBalance(memberId: 'a', currency: 'INR', balanceMinor: 1000),
        MemberBalance(memberId: 'b', currency: 'INR', balanceMinor: 500),
        MemberBalance(memberId: 'c', currency: 'INR', balanceMinor: -700),
        MemberBalance(memberId: 'd', currency: 'INR', balanceMinor: -800),
      ]);

      expect(transfers.length, lessThanOrEqualTo(3));
      expect(transfers.every((t) => t.currency == 'INR'), isTrue);
    });

    test('never nets one currency against another', () {
      final transfers = simplifyDebts(const [
        MemberBalance(memberId: 'a', currency: 'INR', balanceMinor: 50000),
        MemberBalance(memberId: 'b', currency: 'INR', balanceMinor: -50000),
        MemberBalance(memberId: 'a', currency: 'EUR', balanceMinor: -2000),
        MemberBalance(memberId: 'b', currency: 'EUR', balanceMinor: 2000),
      ]);

      // Two separate plans. Cancelling these against each other would hand the
      // exchange-rate risk to whoever the rounding favoured.
      expect(transfers, hasLength(2));
      expect(transfers.map((t) => t.currency).toSet(), {'INR', 'EUR'});
    });
  });

  group('balance and simplify properties', () {
    const cases = 2000;

    test('balances sum to exactly zero per currency', () {
      final gen = EntryGen(864213);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(9));
        final entries = gen.entries(members, 1 + gen.random.nextInt(40));

        final byCurrency = balancesByCurrency(foldBalances(entries));

        for (final currency in byCurrency.entries) {
          expect(
            currency.value.fold(0, (sum, b) => sum + b.balanceMinor),
            0,
            reason: 'seed ${gen.seed}, case $i, currency ${currency.key}',
          );
        }
      }
    });

    test('every generated entry satisfies the server-side invariant', () {
      final gen = EntryGen(5150);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(1 + gen.random.nextInt(10));
        for (final entry in gen.entries(members, 10)) {
          expect(
            entry.isBalanced,
            isTrue,
            reason: 'seed ${gen.seed}, case $i, entry ${entry.id}',
          );
        }
      }
    });

    test('simplify preserves every member net position exactly', () {
      final gen = EntryGen(1123581);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(9));
        final entries = gen.entries(members, 1 + gen.random.nextInt(30));
        final balances = foldBalances(entries);

        final transfers = simplifyDebts(balances);

        // Net movement per (member, currency) implied by the plan.
        final movement = <String, int>{};
        for (final transfer in transfers) {
          final from = '${transfer.fromMemberId}|${transfer.currency}';
          final to = '${transfer.toMemberId}|${transfer.currency}';
          movement[from] = (movement[from] ?? 0) + transfer.amountMinor;
          movement[to] = (movement[to] ?? 0) - transfer.amountMinor;
        }

        for (final balance in balances) {
          final key = '${balance.memberId}|${balance.currency}';
          expect(
            movement[key] ?? 0,
            -balance.balanceMinor,
            reason:
                'seed ${gen.seed}, case $i: the plan must move each member '
                'exactly back to zero, no more and no less',
          );
        }
      }
    });

    test('simplify uses at most n-1 payments per currency', () {
      final gen = EntryGen(271828);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(9));
        final entries = gen.entries(members, 1 + gen.random.nextInt(30));
        final byCurrency = balancesByCurrency(foldBalances(entries));

        final transfers = simplifyDebts(foldBalances(entries));

        for (final currency in byCurrency.entries) {
          final count = transfers
              .where((t) => t.currency == currency.key)
              .length;
          expect(
            count,
            lessThanOrEqualTo(currency.value.length - 1),
            reason: 'seed ${gen.seed}, case $i, currency ${currency.key}',
          );
        }
      }
    });

    test('simplify is deterministic for the same balances', () {
      final gen = EntryGen(6180339);
      for (var i = 0; i < cases; i++) {
        final members = gen.memberIds(2 + gen.random.nextInt(9));
        final balances = foldBalances(
          gen.entries(members, 1 + gen.random.nextInt(20)),
        );

        final first = simplifyDebts(balances);
        final again = simplifyDebts([...balances]..shuffle(gen.random));

        expect(again, first, reason: 'seed ${gen.seed}, case $i');
      }
    });

    test(
      'round trip: entries to balances to settlements leaves nothing owed',
      () {
        final gen = EntryGen(20260821);
        for (var i = 0; i < cases; i++) {
          final members = gen.memberIds(2 + gen.random.nextInt(9));
          final entries = gen.entries(members, 1 + gen.random.nextInt(30));

          final transfers = simplifyDebts(foldBalances(entries));
          final settled = [
            ...entries,
            for (var j = 0; j < transfers.length; j++)
              _settlement(transfers[j], j),
          ];

          expect(
            foldBalances(settled),
            isEmpty,
            reason:
                'seed ${gen.seed}, case $i: after paying the suggested '
                'settlements, every balance must be exactly zero',
          );
        }
      },
    );
  });
}
