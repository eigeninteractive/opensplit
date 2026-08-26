import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import 'fake_remote_ledger.dart';

/// One simulated device: its own local database, outbox and sync engine, all
/// talking to a shared server.
class Device {
  Device(this.name, FakeRemoteLedger server)
    : db = AppDatabase(NativeDatabase.memory()) {
    outbox = OutboxQueue(db);
    groups = DriftGroupRepository(db, outbox: outbox);
    entries = DriftEntryRepository(db, outbox: outbox);
    sync = SyncEngine(db: db, api: server, outbox: outbox);
  }

  final String name;
  final AppDatabase db;
  late final OutboxQueue outbox;
  late final DriftGroupRepository groups;
  late final DriftEntryRepository entries;
  late final SyncEngine sync;

  Future<void> close() => db.close();

  Future<List<Entry>> ledger(String groupId) =>
      entries.getEntries(groupId, includeDeleted: true);
}

void main() {
  // Two devices means two AppDatabase instances in one process. They are
  // separate in-memory databases, so the usual warning does not apply.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeRemoteLedger server;
  late Device a;
  late Device b;

  setUp(() {
    server = FakeRemoteLedger();
    a = Device('A', server);
    b = Device('B', server);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// Sets up a group on device A with three members.
  Future<({String groupId, String ravi, String priya, String arun})>
  seedGroup() async {
    final created = await a.groups.createGroup(
      name: 'Goa Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: 'profile-ravi',
    );
    final priya = await a.groups.addMember(
      created.group.id,
      displayName: 'Priya',
    );
    final arun = await a.groups.addMember(
      created.group.id,
      displayName: 'Arun',
    );
    return (
      groupId: created.group.id,
      ravi: created.creator.id,
      priya: priya.id,
      arun: arun.id,
    );
  }

  group('two devices converge', () {
    test('an expense added on A reaches B with identical balances', () async {
      final g = await seedGroup();

      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner at Toit',
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: 240000},
        ),
        createdBy: g.ravi,
      );

      final pushReport = await a.sync.syncGroup(g.groupId);
      expect(pushReport.isClean, isTrue, reason: '$pushReport');
      expect(pushReport.pushed, 5, reason: 'group, 3 members, 1 entry');

      final pullReport = await b.sync.syncGroup(g.groupId);
      expect(pullReport.pulled, 1);

      // The claim that matters: both devices fold the same journal into the
      // same balances, to the paisa.
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
      expect(
        foldBalances(
          await b.ledger(g.groupId),
        ).map((x) => '${x.memberId}:${x.balanceMinor}'),
        containsAll(['${g.ravi}:160000']),
      );
    });

    test('edits made on both devices converge on the same journal', () async {
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: 240000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      // Each device adds something of its own while the other is unaware.
      await b.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 90000,
          description: 'Auto to the beach',
          split: EqualSplit([g.priya, g.arun]),
          payerAmounts: {g.priya: 90000},
        ),
        createdBy: g.priya,
      );
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 60000,
          description: 'Coffee',
          split: EqualSplit([g.ravi, g.arun]),
          payerAmounts: {g.arun: 60000},
        ),
        createdBy: g.arun,
      );

      // Two rounds, because each device has to push before it can see the
      // other's push.
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      await a.sync.syncGroup(g.groupId);

      final ledgerA = await a.ledger(g.groupId);
      final ledgerB = await b.ledger(g.groupId);

      expect(ledgerA, hasLength(3));
      expect(ledgerB, hasLength(3));
      expect(foldBalances(ledgerA), foldBalances(ledgerB));
      expect(
        foldBalances(ledgerA).fold(0, (sum, x) => sum + x.balanceMinor),
        0,
      );
    });

    test('a soft delete propagates rather than lingering on B', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 120000,
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 120000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      expect(foldBalances(await b.ledger(g.groupId)), hasLength(2));

      await a.entries.delete(entry.id);
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      final onB = await b.ledger(g.groupId);
      expect(onB.single.isDeleted, isTrue);
      expect(
        foldBalances(onB),
        isEmpty,
        reason: 'a deletion is a delta; it cannot be filtered out of the feed',
      );
    });

    test('the last write wins, judged by the server clock', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Original',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      // Both edit the same entry while offline from each other.
      await a.entries.update(
        entry.id,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Edited on A',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
      );
      await b.entries.update(
        entry.id,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Edited on B',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
      );

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId); // B pushes second, so B wins.
      await a.sync.syncGroup(g.groupId);

      expect((await a.ledger(g.groupId)).single.description, 'Edited on B');
      expect((await b.ledger(g.groupId)).single.description, 'Edited on B');
    });
  });

  group('the server is the backstop', () {
    test('an unbalanced entry is rejected and never stored', () async {
      final g = await seedGroup();
      final good = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );

      // Corrupt the row behind the repository's back, the way a client bug
      // would. This is precisely what the deferred trigger exists to catch.
      await (a.db.update(a.db.entryShares)
            ..where((t) => t.entryId.equals(good.id)))
          .write(const EntrySharesCompanion(amountMinor: Value(1)));
      await a.outbox.enqueue(OutboxTarget.entry, good.id);

      final report = await a.sync.syncGroup(g.groupId);

      expect(report.failed, greaterThan(0));
      await b.sync.syncGroup(g.groupId);
      expect(
        await b.ledger(g.groupId),
        isEmpty,
        reason: 'bad data must not be able to reach another device',
      );
    });

    test(
      'a permanently rejected item is set aside, not retried forever',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 100000,
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 100000},
          ),
          createdBy: g.ravi,
        );
        await (a.db.update(a.db.entryShares)
              ..where((t) => t.entryId.equals(entry.id)))
            .write(const EntrySharesCompanion(amountMinor: Value(1)));
        await a.outbox.enqueue(OutboxTarget.entry, entry.id);

        await a.sync.syncGroup(g.groupId);

        // Out of the queue, so it cannot wedge everything behind it...
        expect(await a.outbox.pendingCount(), 0);

        // ...but not silently discarded. A write the user believes they made
        // must remain accounted for somewhere.
        final dead = await a.outbox.deadLetters();
        expect(dead, hasLength(1));
        expect(dead.single.lastError, contains('does not balance'));
      },
    );

    // Being "accounted for somewhere" is worth nothing if nowhere is a screen.
    // A refused write leaves an entry that looks saved on this device and does
    // not exist for anyone else, which surfaces weeks later as two people
    // reading different balances. These two tests are the difference between
    // that and a banner.
    test('a refused write is described, not just recorded', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: "Dinner at Britto's",
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await (a.db.update(a.db.entryShares)
            ..where((t) => t.entryId.equals(entry.id)))
          .write(const EntrySharesCompanion(amountMinor: Value(1)));
      await a.outbox.enqueue(OutboxTarget.entry, entry.id);

      await a.sync.syncGroup(g.groupId);

      final failures = await a.outbox.watchDeadLetters().first;
      expect(failures, hasLength(1));
      expect(
        failures.single.label,
        "Dinner at Britto's",
        reason: 'the user has to recognise which expense this is',
      );
      expect(failures.single.reason, contains('does not balance'));
      expect(failures.single.target, OutboxTarget.entry);
    });

    test('a refused write can be retried once its cause is fixed', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await (a.db.update(a.db.entryShares)
            ..where((t) => t.entryId.equals(entry.id)))
          .write(const EntrySharesCompanion(amountMinor: Value(1)));
      await a.outbox.enqueue(OutboxTarget.entry, entry.id);
      await a.sync.syncGroup(g.groupId);
      expect(await a.outbox.deadLetters(), hasLength(1));

      // Whatever the server objected to, put it right. "Permanent" only ever
      // meant permanent against the server as it stood.
      await (a.db.update(a.db.entryShares)
            ..where((t) => t.entryId.equals(entry.id)))
          .write(const EntrySharesCompanion(amountMinor: Value(50000)));

      expect(await a.outbox.retryDeadLetters(), 1);
      await a.sync.syncGroup(g.groupId);

      expect(await a.outbox.deadLetters(), isEmpty);
      expect(await a.outbox.pendingCount(), 0, reason: 'it landed');
      expect(await a.outbox.watchDeadLetters().first, isEmpty);
    });

    test('a retried push does not create a second entry', () async {
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );

      await a.sync.syncGroup(g.groupId);
      final afterFirst = server.entryCount;

      // Simulate a response lost in transit: the write landed, the client never
      // heard, so it queues the same row again.
      final stored = (await a.ledger(g.groupId)).single;
      await a.outbox.enqueue(OutboxTarget.entry, stored.id);
      await a.sync.syncGroup(g.groupId);

      expect(server.entryCount, afterFirst);
      expect(server.upsertCalls, greaterThan(1), reason: 'it really did retry');
    });
  });

  group('the cursor', () {
    test('pages through more entries than fit in one request', () async {
      final g = await seedGroup();
      for (var i = 0; i < 25; i++) {
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 1000 + i,
            description: 'Expense $i',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 1000 + i},
          ),
          createdBy: g.ravi,
        );
      }
      await a.sync.syncGroup(g.groupId);

      final small = SyncEngine(
        db: b.db,
        api: server,
        outbox: b.outbox,
        pageSize: 4,
      );
      await small.syncGroup(g.groupId);

      expect(await b.ledger(g.groupId), hasLength(25));
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
    });

    test('does not stall on a batch sharing one timestamp', () async {
      // Postgres `now()` is transaction time, so every row written in one
      // transaction carries an identical `updated_at`. A timestamp-only cursor
      // either skips the rest of such a batch forever or re-reads it forever.
      final g = await seedGroup();
      for (var i = 0; i < 12; i++) {
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 5000,
            description: 'Batched $i',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 5000},
          ),
          createdBy: g.ravi,
        );
      }

      await server.inOneTransaction(() => a.sync.push());

      final stamps = <DateTime>{
        for (final e in await a.ledger(g.groupId)) e.updatedAt,
      };
      expect(stamps, hasLength(1), reason: 'the batch really does share one');

      final small = SyncEngine(
        db: b.db,
        api: server,
        outbox: b.outbox,
        pageSize: 5,
      );
      await small.syncGroup(g.groupId);

      expect(await b.ledger(g.groupId), hasLength(12));
    });

    test('a second sync with no changes pulls nothing', () async {
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);

      expect((await b.sync.syncGroup(g.groupId)).pulled, 1);
      expect(
        (await b.sync.syncGroup(g.groupId)).pulled,
        0,
        reason: 'the cursor must not re-deliver what it already applied',
      );
    });
  });

  group('offline replay', () {
    test('a queue built with no server drains once it appears', () async {
      final g = await seedGroup();
      for (var i = 0; i < 5; i++) {
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 10000 * (i + 1),
            description: 'Offline $i',
            split: EqualSplit([g.ravi, g.priya, g.arun]),
            payerAmounts: {g.ravi: 10000 * (i + 1)},
          ),
          createdBy: g.ravi,
        );
      }

      // Nothing has been synced yet: everything so far is queued.
      expect(await a.outbox.pendingCount(), 9, reason: 'group + 3 members + 5');

      await a.sync.syncGroup(g.groupId);
      expect(await a.outbox.pendingCount(), 0);

      await b.sync.syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), hasLength(5));
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
    });

    test('an offline edit does not reorder a row ahead of its group', () async {
      // The whole group is created offline and then touched again before
      // anything has been pushed. Every edit re-queues its row, and the outbox
      // used to date the item from the latest touch rather than the first —
      // which put the group behind the members and entries that reference it.
      // The server refuses those permanently, so they went to the dead letters
      // and the group was stuck with nobody able to see it.
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 40000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 40000},
        ),
        createdBy: g.ravi,
      );

      final group = (await a.groups.getGroup(g.groupId))!;
      await a.groups.updateGroup(group.copyWith(name: 'Goa trip'));
      await a.groups.renameMember(g.priya, 'Priya S');

      expect(
        [for (final row in await a.outbox.due()) row.operation],
        ['group', 'member', 'member', 'member', 'entry'],
        reason: 'the group has to reach the server before anything naming it',
      );

      final report = await a.sync.syncGroup(g.groupId);
      expect(report.failed, 0, reason: 'nothing should be refused');
      expect(await a.outbox.deadLetters(), isEmpty);
      expect(await a.outbox.pendingCount(), 0);

      await b.sync.syncGroup(g.groupId);
      expect((await b.groups.getGroup(g.groupId))!.name, 'Goa trip');
      expect(await b.ledger(g.groupId), hasLength(1));
    });
  });

  group('group and member rows', () {
    test(
      'a local rename survives a pull that runs before it is pushed',
      () async {
        final created = await a.groups.createGroup(
          name: 'Goa Trip',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Ravi',
          creatorProfileId: 'ravi',
        );
        await a.sync.syncGroup(created.group.id);
        await b.sync.syncGroup(created.group.id);

        // Renamed on A while offline: the edit is in the local row and queued,
        // but has not reached the server.
        await a.groups.updateGroup(
          created.group.copyWith(name: 'Goa Trip 2026'),
        );

        // A pull arrives first — this is the case that used to silently discard
        // the rename, because the pull applied the server row unconditionally.
        await a.sync.pull(created.group.id);

        final local = await a.groups.getGroup(created.group.id);
        expect(local!.name, 'Goa Trip 2026');
      },
    );

    test('a remote rename still wins once it is genuinely newer', () async {
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      await a.sync.syncGroup(created.group.id);
      await b.sync.syncGroup(created.group.id);

      // B renames it and pushes, so the server row carries a later stamp.
      final onB = await b.groups.getGroup(created.group.id);
      await b.groups.updateGroup(onB!.copyWith(name: 'Renamed on B'));
      await b.sync.syncGroup(created.group.id);

      await a.sync.syncGroup(created.group.id);
      final local = await a.groups.getGroup(created.group.id);
      expect(local!.name, 'Renamed on B');
    });

    test('a member rename converges across devices', () async {
      final created = await a.groups.createGroup(
        name: 'Flat 4B',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      final priya = await a.groups.addMember(
        created.group.id,
        displayName: 'Priya',
      );
      await a.sync.syncGroup(created.group.id);
      await b.sync.syncGroup(created.group.id);

      await b.groups.renameMember(priya.id, 'Priya S');
      await b.sync.syncGroup(created.group.id);
      await a.sync.syncGroup(created.group.id);

      final members = await a.groups.getMembers(created.group.id);
      expect(
        members.firstWhere((m) => m.id == priya.id).displayName,
        'Priya S',
      );
    });
  });

  group('exchange rates', () {
    test('arrive with sync and are then left alone', () async {
      server.publishFxRate(asOf: '2026-08-20', currency: 'USD', rate: 1);
      server.publishFxRate(asOf: '2026-08-20', currency: 'INR', rate: 95.43);

      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      await a.sync.syncGroup(created.group.id);

      final stored = await a.db.select(a.db.fxRates).get();
      expect(stored, hasLength(2));

      // Rates are immutable once published, so a settled device asks for
      // everything on or after the newest date it holds and gets that one day
      // back — never the whole history again.
      final pullsAfterFirst = server.fxPulls;
      await a.sync.syncGroup(created.group.id);
      expect(server.fxPulls, pullsAfterFirst + 1);
      expect(await a.db.select(a.db.fxRates).get(), hasLength(2));
    });

    test(
      'a later publication is added without disturbing the earlier one',
      () async {
        server.publishFxRate(asOf: '2026-08-20', currency: 'INR', rate: 95.43);

        final created = await a.groups.createGroup(
          name: 'Goa Trip',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Ravi',
          creatorProfileId: 'ravi',
        );
        await a.sync.syncGroup(created.group.id);

        server.publishFxRate(asOf: '2026-08-21', currency: 'INR', rate: 95.70);
        await a.sync.syncGroup(created.group.id);

        final stored = await a.db.select(a.db.fxRates).get()
          ..sort((x, y) => x.asOf.compareTo(y.asOf));
        expect(stored.map((r) => r.asOf), ['2026-08-20', '2026-08-21']);
        // History must not be rewritten: an entry backdated to the 20th still
        // has to price at the 20th's rate.
        expect(stored.first.rate, closeTo(95.43, 1e-9));
      },
    );

    test('a rate failure never fails a sync that carries money', () async {
      server.failFxPulls = true;

      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      final report = await a.sync.syncGroup(created.group.id);
      expect(report.isClean, isTrue);
    });
  });

  group('finding groups this device has never seen', () {
    // The gap that made a second device, a reinstall, and "sign in on another
    // device" all show an empty app: everything else in the sync API is scoped
    // to a groupId the caller has to already know.
    test('a fresh device discovers the groups it belongs to', () async {
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      await a.entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'INR',
          amountMinor: 240000,
          description: 'Dinner',
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 240000},
        ),
        createdBy: created.creator.id,
      );
      await a.sync.syncGroup(created.group.id);

      // Device B holds nothing at all and is signed in as the same person.
      server.signedInProfileId = 'profile-ravi';
      expect(await b.db.select(b.db.groups).get(), isEmpty);

      final found = await b.sync.discoverGroups();
      expect(found, [created.group.id]);

      for (final id in found) {
        await b.sync.syncGroup(id);
      }

      final groups = await b.db.select(b.db.groups).get();
      expect(groups.single.name, 'Goa Trip');
      expect((await b.ledger(created.group.id)).single.amountMinor, 240000);
    });

    test('a group left behind is not rediscovered', () async {
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      await a.sync.syncGroup(created.group.id);

      await a.groups.leaveGroup(
        groupId: created.group.id,
        memberId: created.creator.id,
      );
      await a.sync.syncGroup(created.group.id);

      server.signedInProfileId = 'profile-ravi';
      expect(await b.sync.discoverGroups(), isEmpty);
    });

    test('local groups survive a server that cannot be reached', () async {
      // Being offline must not empty the sweep and skip pushing the very rows
      // that are queued to go out.
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      server.signedInProfileId = null;

      expect(await a.sync.discoverGroups(), [created.group.id]);
    });
  });

  group('pushing a member', () {
    test('does not blank a claim this device has not pulled yet', () async {
      // The race: somebody redeems their invite, and before this device learns
      // of it the user renames them. profile_id must not travel with that.
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      final priya = await a.groups.addMember(
        created.group.id,
        displayName: 'Priya',
      );
      await a.sync.syncGroup(created.group.id);

      // Priya claims her place on the server, as redeem_invite would.
      server.claimMember(priya.id, 'profile-priya');

      // Device A still believes she is a placeholder, and renames her.
      await a.groups.renameMember(priya.id, 'Priya S');
      await a.sync.syncGroup(created.group.id);

      // The server's own view, read before anything else touches it: the
      // rename has to have landed, and the claim has to have survived it.
      final onServer = (await server.pullMembers(
        created.group.id,
      )).firstWhere((m) => m.id == priya.id);
      expect(onServer.displayName, 'Priya S', reason: 'the rename still lands');
      expect(
        onServer.profileId,
        'profile-priya',
        reason:
            'the push carried a stale profile_id of null and un-joined the '
            'person who had just claimed their invite',
      );

      // And she can therefore still find the group from a device of her own.
      server.signedInProfileId = 'profile-priya';
      expect(await b.sync.discoverGroups(), [created.group.id]);
    });
  });

  group('a name follows the account, not the group', () {
    test('a rename by somebody else arrives on the next sync', () async {
      final server = FakeRemoteLedger();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = SyncEngine(db: db, api: server, outbox: OutboxQueue(db));

      // Priya is on the server under the name her account carries.
      server.seedProfile(
        const Profile(id: 'priya-account', displayName: 'Priya'),
      );

      await engine.pullProfiles();
      final first = await DriftProfileRepository(db).byId('priya-account');
      expect(first?.displayName, 'Priya');

      // She renames herself on her own phone. Nothing about any group changes
      // — which is the point: the name is not copied into a member row per
      // group any more, so this is one write reaching everybody.
      server.seedProfile(
        const Profile(id: 'priya-account', displayName: 'Priya S'),
      );

      await engine.pullProfiles();
      final second = await DriftProfileRepository(db).byId('priya-account');
      expect(
        second?.displayName,
        'Priya S',
        reason: 'a rename has to reach the people who actually read the name',
      );
    });

    test('the cursor stops it re-fetching what it already has', () async {
      final server = FakeRemoteLedger();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final engine = SyncEngine(db: db, api: server, outbox: OutboxQueue(db));

      server.seedProfile(const Profile(id: 'a', displayName: 'Ravi'));

      await engine.pullProfiles();
      expect(
        server.lastProfilesSince,
        isNull,
        reason: 'the first pull holds nothing, so it asks for everything',
      );

      await engine.pullProfiles();
      expect(
        server.lastProfilesSince,
        isNotNull,
        reason:
            'the second asks only for what changed after the newest row '
            'it already has — without a cursor this refetches every profile '
            'in every group, on every sync, forever',
      );
    });
  });

  group('the outbox is a set of dirty rows, not a log', () {
    test('re-dirtying a row keeps when it first went dirty', () async {
      final clock = _StepClock();
      final outbox = OutboxQueue(a.db, clock: clock.now);

      await outbox.enqueue(OutboxTarget.group, 'g1');
      final first = (await outbox.due()).single.createdAt;

      await outbox.enqueue(OutboxTarget.group, 'g1');
      expect(
        (await outbox.due()).single.createdAt,
        first,
        reason: 'a second edit is not the row becoming new',
      );
    });

    test('re-dirtying a row does clear its retry state', () async {
      final outbox = OutboxQueue(a.db);
      await outbox.enqueue(OutboxTarget.group, 'g1');
      await outbox.fail(
        OutboxQueue.idFor(OutboxTarget.group, 'g1'),
        'refused',
        permanent: true,
      );
      expect(await outbox.deadLetters(), hasLength(1));

      // Whatever the server objected to may be exactly what this edit changed.
      await outbox.enqueue(OutboxTarget.group, 'g1');
      expect(await outbox.deadLetters(), isEmpty);
      expect(await outbox.due(), hasLength(1));
    });
  });
}

/// A clock that never returns the same instant twice, so an ordering assertion
/// cannot pass by two writes happening to share a microsecond.
class _StepClock {
  DateTime _at = DateTime.utc(2026, 8, 26);

  DateTime now() => _at = _at.add(const Duration(seconds: 1));
}
