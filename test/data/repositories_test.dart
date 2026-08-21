import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_currency_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/mappers.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/member.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;
  late DriftEntryRepository entries;
  late DriftCurrencyRepository currencies;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = DriftGroupRepository(db);
    entries = DriftEntryRepository(db);
    currencies = DriftCurrencyRepository(db);
  });

  tearDown(() => db.close());

  group('reference data', () {
    test('is seeded on creation so the app works before any network', () async {
      final all = await currencies.all();
      expect(all, hasLength(16));

      final inr = await currencies.byCode('INR');
      expect(inr!.exponent, 2);
      expect((await currencies.byCode('JPY'))!.exponent, 0);
      expect((await currencies.byCode('KWD'))!.exponent, 3);
    });

    test('ships category presets with ids fixed to match the server', () async {
      final rows = await db.select(db.categories).get();
      expect(rows, hasLength(10));
      expect(
        rows.map((r) => r.id),
        contains('00000000-0000-4000-8000-000000000001'),
      );
      expect(rows.every((r) => r.groupId == null), isTrue);
    });
  });

  group('groups and members', () {
    test('creating a group creates its owner in the same breath', () async {
      final created = await groups.createGroup(
        name: '  Goa Trip  ',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
      );

      expect(created.group.name, 'Goa Trip', reason: 'name is trimmed');
      expect(created.owner.role, MemberRole.owner);
      expect(await groups.getMembers(created.group.id), hasLength(1));
    });

    test('a placeholder member is a full member with no account', () async {
      final created = await groups.createGroup(
        name: 'Flat 4B',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
      );

      final arun = await groups.addMember(
        created.group.id,
        displayName: 'Arun',
      );

      expect(arun.isPlaceholder, isTrue);
      expect(arun.isActive, isTrue);
      expect(await groups.getMembers(created.group.id), hasLength(2));
    });

    test('removing a member marks them left rather than deleting', () async {
      final created = await groups.createGroup(
        name: 'Flat 4B',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
      );
      final arun = await groups.addMember(
        created.group.id,
        displayName: 'Arun',
      );

      await groups.removeMember(arun.id);

      expect(await groups.getMembers(created.group.id), hasLength(1));
      final withLeft = await groups
          .watchMembers(created.group.id, includeLeft: true)
          .first;
      expect(withLeft, hasLength(2));
      expect(withLeft.firstWhere((m) => m.id == arun.id).isActive, isFalse);
    });

    test('archived groups drop out of the default list', () async {
      final created = await groups.createGroup(
        name: 'Old Trip',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
      );

      await groups.setArchived(created.group.id, archived: true);

      expect(await groups.watchGroups().first, isEmpty);
      expect(
        await groups.watchGroups(includeArchived: true).first,
        hasLength(1),
      );
    });
  });

  group('entries', () {
    late String groupId;
    late String ravi;
    late String priya;
    late String arun;

    setUp(() async {
      final created = await groups.createGroup(
        name: 'Flat 4B',
        defaultCurrency: 'INR',
        ownerDisplayName: 'Ravi',
      );
      groupId = created.group.id;
      ravi = created.owner.id;
      priya = (await groups.addMember(groupId, displayName: 'Priya')).id;
      arun = (await groups.addMember(groupId, displayName: 'Arun')).id;
    });

    test('an equal split stores balanced payers and shares', () async {
      final entry = await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner at Toit',
          split: EqualSplit([ravi, priya, arun]),
          payerAmounts: {ravi: 240000},
        ),
        createdBy: ravi,
      );

      expect(entry.isBalanced, isTrue);
      expect(entry.shares.map((s) => s.amountMinor), [80000, 80000, 80000]);
      expect(entry.clientKey, entry.id, reason: 'retries must be idempotent');
    });

    test('multiple payers on one bill round-trip through storage', () async {
      await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 300000,
          description: 'Groceries and drinks',
          split: EqualSplit([ravi, priya, arun]),
          payerAmounts: {ravi: 200000, priya: 100000},
        ),
        createdBy: ravi,
      );

      final loaded = (await entries.getEntries(groupId)).single;
      expect(loaded.payers, hasLength(2));
      expect(loaded.isBalanced, isTrue);
      expect(
        foldBalances([loaded]).fold(0, (sum, b) => sum + b.balanceMinor),
        0,
      );
    });

    test('a draft that does not balance is never written', () async {
      await expectLater(
        entries.create(
          EntryDraft(
            groupId: groupId,
            currency: 'INR',
            amountMinor: 100000,
            split: EqualSplit([ravi, priya]),
            payerAmounts: {ravi: 90000},
          ),
          createdBy: ravi,
        ),
        throwsA(isA<SplitException>()),
      );

      expect(await entries.getEntries(groupId), isEmpty);
    });

    test('editing replaces shares and keeps creation metadata', () async {
      final original = await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 240000,
          split: EqualSplit([ravi, priya, arun]),
          payerAmounts: {ravi: 240000},
        ),
        createdBy: ravi,
      );

      final edited = await entries.update(
        original.id,
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 240000,
          split: SharesSplit({ravi: 2, priya: 1, arun: 1}),
          payerAmounts: {ravi: 240000},
        ),
      );

      expect(edited.id, original.id);
      expect(edited.createdAt, original.createdAt);
      expect(edited.clientKey, original.clientKey);
      expect(edited.updatedAt.isAfter(original.updatedAt), isTrue);
      expect(edited.splitKind, SplitKind.shares);

      final loaded = (await entries.getEntries(groupId)).single;
      expect(loaded.shares, hasLength(3));
      expect(loaded.isBalanced, isTrue);
      expect(
        loaded.shares.firstWhere((s) => s.memberId == ravi).amountMinor,
        120000,
      );
    });

    test('deleting is soft, and the deletion is itself a delta', () async {
      final entry = await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: 100000},
        ),
        createdBy: ravi,
      );

      await entries.delete(entry.id);

      expect(await entries.getEntries(groupId), isEmpty);
      final withDeleted = await entries.getEntries(
        groupId,
        includeDeleted: true,
      );
      expect(withDeleted, hasLength(1));
      expect(withDeleted.single.isDeleted, isTrue);
      expect(
        withDeleted.single.updatedAt.isAfter(entry.updatedAt),
        isTrue,
        reason: 'other devices find the deletion by its updated_at cursor',
      );
      expect(foldBalances(withDeleted), isEmpty);
    });

    test('a settlement cancels exactly the debt it is meant to', () async {
      await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 120000,
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: 120000},
        ),
        createdBy: ravi,
      );

      var balances = foldBalances(await entries.getEntries(groupId));
      expect(balances.minorFor(priya, 'INR'), -60000);

      await entries.create(
        EntryDraft.settlement(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 60000,
          fromMemberId: priya,
          toMemberId: ravi,
        ),
        createdBy: priya,
      );

      balances = foldBalances(await entries.getEntries(groupId));
      expect(balances, isEmpty, reason: 'the group is fully settled');
    });

    test('a settlement to yourself is rejected', () {
      expect(
        () => EntryDraft.settlement(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 100,
          fromMemberId: ravi,
          toMemberId: ravi,
        ),
        throwsA(isA<SplitException>()),
      );
    });

    test('foreign keys stop a share pointing outside the group', () async {
      await expectLater(
        db
            .into(db.entryShares)
            .insert(
              EntrySharesCompanion.insert(
                entryId: 'no-such-entry',
                memberId: ravi,
                amountMinor: 100,
                weightMicros: const Value(null),
              ),
            ),
        throwsA(anything),
        reason: 'PRAGMA foreign_keys must actually be on',
      );
    });

    test('the entry stream re-emits when a child row changes', () async {
      final emissions = <int>[];
      final subscription = entries
          .watchEntries(groupId)
          .listen((list) => emissions.add(list.length));

      await Future<void>.delayed(Duration.zero);
      await entries.create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([ravi, priya]),
          payerAmounts: {ravi: 100000},
        ),
        createdBy: ravi,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(emissions.first, 0);
      expect(emissions.last, 1);
    });
  });
}
