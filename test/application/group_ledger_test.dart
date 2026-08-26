import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// The fold every group screen reads.
///
/// Two things here are newer than the rest of it. `isSettledUp` is what the
/// members screen asks before offering to remove somebody — the server refuses
/// otherwise — and `pastMembers` is what lets a departed member's name still
/// resolve, which it did not: the balances panel iterates balances rather than
/// members, so somebody who left owing money rendered as "—".
void main() {
  final now = DateTime.utc(2026, 8, 27);
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<GroupLedger> ledger() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // ProviderContainer.test rather than the bare constructor: Riverpod 3
    // reserves the latter for internal use and it fails on first read.
    final container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        currentAccountIdProvider.overrideWithValue(testAccountId),
        signedInProvider.overrideWithValue(true),
      ],
    );

    // Holds the derived provider open while the drift streams beneath it emit,
    // then waits for it the way the UI does: it is null only until the local
    // database answers, which is a microtask rather than a round trip.
    container.listen(groupLedgerProvider('g1'), (_, _) {});
    for (var i = 0; i < 100; i++) {
      final resolved = container.read(groupLedgerProvider('g1'));
      if (resolved != null) return resolved;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('the ledger never resolved');
  }

  /// Ravi paid ₹400 split with Priya, who then left without settling. Arun is
  /// in the group and owes nothing.
  Future<void> seed() async {
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            name: 'Goa',
            defaultCurrency: 'INR',
            createdAt: now,
          ),
        );
    await db.batch((batch) {
      batch.insertAll(db.members, [
        MembersCompanion.insert(
          id: 'm-ravi',
          groupId: 'g1',
          profileId: const Value(testAccountId),
          displayName: 'Ravi',
          joinedAt: now,
        ),
        MembersCompanion.insert(
          id: 'm-priya',
          groupId: 'g1',
          displayName: 'Priya',
          joinedAt: now,
          leftAt: Value(now),
        ),
        MembersCompanion.insert(
          id: 'm-arun',
          groupId: 'g1',
          displayName: 'Arun',
          joinedAt: now,
        ),
      ]);
    });
    await db
        .into(db.entries)
        .insert(
          EntriesCompanion.insert(
            id: 'e1',
            groupId: 'g1',
            kind: EntryKind.expense,
            currency: 'INR',
            amountMinor: 40000,
            entryDate: now,
            splitKind: SplitKind.equal,
            createdBy: 'm-ravi',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.batch((batch) {
      batch.insert(
        db.entryPayers,
        EntryPayersCompanion.insert(
          entryId: 'e1',
          memberId: 'm-ravi',
          amountMinor: 40000,
        ),
      );
      batch.insertAll(db.entryShares, [
        EntrySharesCompanion.insert(
          entryId: 'e1',
          memberId: 'm-ravi',
          amountMinor: 20000,
        ),
        EntrySharesCompanion.insert(
          entryId: 'e1',
          memberId: 'm-priya',
          amountMinor: 20000,
        ),
      ]);
    });
  }

  test('departed members are out of the roster but still have names', () async {
    await seed();
    final group = await ledger();

    expect(
      [for (final m in group.members) m.id],
      ['m-ravi', 'm-arun'],
      reason: 'a picker must not offer somebody who has left',
    );
    expect([for (final m in group.pastMembers) m.id], ['m-priya']);

    expect(
      group.nameOf('m-priya'),
      'Priya',
      reason: 'she still owes ₹200, and the balances panel has to name her',
    );
  });

  test('settled means holding nothing in any currency', () async {
    await seed();
    final group = await ledger();

    expect(group.isSettledUp('m-arun'), isTrue, reason: 'never in an expense');
    expect(group.isSettledUp('m-ravi'), isFalse, reason: 'owed ₹200');
    expect(group.isSettledUp('m-priya'), isFalse, reason: 'owes ₹200');
  });

  test('a member with no expenses at all is settled', () async {
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            name: 'Empty',
            defaultCurrency: 'INR',
            createdAt: now,
          ),
        );
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm-ravi',
            groupId: 'g1',
            profileId: const Value(testAccountId),
            displayName: 'Ravi',
            joinedAt: now,
          ),
        );

    expect((await ledger()).isSettledUp('m-ravi'), isTrue);
  });
}
