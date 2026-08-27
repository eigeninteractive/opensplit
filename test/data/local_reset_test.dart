import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/local_reset.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

/// Signing out has to actually clear the device.
///
/// This exists because it did not. `entry_events` was missing from the list,
/// its references declared no ON DELETE action, and so `delete from entries`
/// failed on a foreign key — which meant sign-out threw, and account deletion
/// threw *after* the server had already removed the account, leaving somebody
/// told their deletion failed when it had not.
///
/// The device only holds activity rows once it has synced a group with an
/// expense in it, which is why nothing caught this: every path that creates
/// them is a server round trip.
void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 8, 26);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Everything a device holds after a sync: a group, a member, an expense
  /// with both halves of its split, an activity feed, a cursor and a queued
  /// write.
  Future<void> seedSyncedLedger() async {
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            name: 'Goa',
            defaultCurrency: 'INR',
            createdBy: const Value('p1'),
            createdAt: now,
          ),
        );
    await db
        .into(db.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p1',
            displayName: const Value('Ravi'),
          ),
        );
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm1',
            groupId: 'g1',
            profileId: const Value('p1'),
            displayName: 'Ravi',
            joinedAt: now,
          ),
        );
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
            createdBy: 'm1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.entryPayers)
        .insert(
          EntryPayersCompanion.insert(
            entryId: 'e1',
            memberId: 'm1',
            amountMinor: 40000,
          ),
        );
    await db
        .into(db.entryShares)
        .insert(
          EntrySharesCompanion.insert(
            entryId: 'e1',
            memberId: 'm1',
            amountMinor: 40000,
          ),
        );
    await db
        .into(db.entryEvents)
        .insert(
          EntryEventsCompanion.insert(
            id: 'ev1',
            entryId: 'e1',
            groupId: 'g1',
            actorId: 'm1',
            kind: 'created',
            createdAt: now,
          ),
        );
    await db
        .into(db.syncCursors)
        .insert(SyncCursorsCompanion.insert(groupId: 'g1', cursor: Value(now)));
    await OutboxQueue(db).enqueue(OutboxTarget.entry, 'e1');
  }

  test('a synced device can be cleared', () async {
    await seedSyncedLedger();

    // The bug was here: this threw SqliteException(787) rather than returning.
    await forgetLocalLedger(db);

    expect(await db.select(db.groups).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
    expect(await db.select(db.entries).get(), isEmpty);
    expect(await db.select(db.entryPayers).get(), isEmpty);
    expect(await db.select(db.entryShares).get(), isEmpty);
    expect(
      await db.select(db.entryEvents).get(),
      isEmpty,
      reason: 'an activity feed is somebody\'s spending, described',
    );
    expect(await db.select(db.profiles).get(), isEmpty);
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await db.select(db.syncCursors).get(), isEmpty);
  });

  test('reference data survives, because it belongs to no account', () async {
    await seedSyncedLedger();
    await forgetLocalLedger(db);

    expect(await db.select(db.currencies).get(), isNotEmpty);
    expect(await db.select(db.categories).get(), isNotEmpty);
  });

  test('clearing a device twice is not an error', () async {
    await seedSyncedLedger();
    await forgetLocalLedger(db);
    await forgetLocalLedger(db);
  });
}
