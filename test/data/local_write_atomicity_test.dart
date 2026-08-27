import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/local_reset.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'a session cleared by sign-out cannot accept late editor writes',
    () async {
      final groups = DriftGroupRepository(db, outbox: OutboxQueue(db));
      await forgetLocalLedger(db, requireSynced: true);
      await expectLater(
        groups.createGroup(
          name: 'Late edit',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Test',
        ),
        throwsStateError,
      );
      expect(await db.select(db.groups).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
    },
  );

  test('sign-out refuses to clear an unresolved local write', () async {
    await OutboxQueue(db).enqueue(OutboxTarget.group, 'pending');
    await expectLater(
      forgetLocalLedger(db, requireSynced: true),
      throwsStateError,
    );
    expect(await db.select(db.outbox).get(), hasLength(1));
  });

  test('group and creator roll back if their queue write fails', () async {
    final groups = DriftGroupRepository(db, outbox: _RefusingOutbox(db));
    await expectLater(
      groups.createGroup(
        name: 'Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Test',
      ),
      throwsStateError,
    );
    expect(await db.select(db.groups).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
  });

  test('a profile cannot be stored without its pending write', () async {
    final profiles = DriftProfileRepository(db, outbox: _RefusingOutbox(db));
    await expectLater(
      profiles.upsert(const Profile(id: 'profile', displayName: 'Test')),
      throwsStateError,
    );
    expect(await db.select(db.profiles).get(), isEmpty);
  });

  test('an entry and its history roll back if enqueue fails', () async {
    final group = await DriftGroupRepository(db).createGroup(
      name: 'Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Test',
    );
    final entries = DriftEntryRepository(db, outbox: _RefusingOutbox(db));
    await expectLater(
      entries.create(
        EntryDraft(
          groupId: group.group.id,
          currency: 'INR',
          amountMinor: 100,
          description: 'Dinner',
          payerAmounts: {group.creator.id: 100},
          split: EqualSplit([group.creator.id]),
        ),
        createdBy: group.creator.id,
      ),
      throwsStateError,
    );
    expect(await db.select(db.entries).get(), isEmpty);
    expect(await db.select(db.entrySnapshots).get(), isEmpty);
  });

  test(
    'an old editor cannot overwrite or delete a newer local version',
    () async {
      final group = await DriftGroupRepository(db).createGroup(
        name: 'Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Test',
      );
      final entries = DriftEntryRepository(db);
      EntryDraft draft(int amount) => EntryDraft(
        groupId: group.group.id,
        currency: 'INR',
        amountMinor: amount,
        description: 'Dinner',
        payerAmounts: {group.creator.id: amount},
        split: EqualSplit([group.creator.id]),
      );
      final opened = await entries.create(
        draft(100),
        createdBy: group.creator.id,
      );
      await entries.update(opened.id, draft(200), actorId: group.creator.id);

      await expectLater(
        entries.update(
          opened.id,
          draft(300),
          actorId: group.creator.id,
          expected: opened,
        ),
        throwsA(isA<StaleEntryException>()),
      );
      await expectLater(
        entries.delete(opened.id, actorId: group.creator.id, expected: opened),
        throwsA(isA<StaleEntryException>()),
      );
      expect((await entries.getEntry(opened.id))!.amountMinor, 200);
      expect((await entries.getEntry(opened.id))!.isDeleted, isFalse);
    },
  );
}

class _RefusingOutbox extends OutboxQueue {
  _RefusingOutbox(super.db);

  @override
  Future<void> enqueue(OutboxTarget target, String targetId) async {
    throw StateError('Simulated queue failure');
  }
}
