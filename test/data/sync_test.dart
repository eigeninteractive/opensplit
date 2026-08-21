import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
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
      ownerDisplayName: 'Ravi',
      ownerProfileId: 'profile-ravi',
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
      ravi: created.owner.id,
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
  });

  group('group and member rows', () {
    test(
      'a local rename survives a pull that runs before it is pushed',
      () async {
        final created = await a.groups.createGroup(
          name: 'Goa Trip',
          defaultCurrency: 'INR',
          ownerDisplayName: 'Ravi',
          ownerProfileId: 'ravi',
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
        ownerDisplayName: 'Ravi',
        ownerProfileId: 'ravi',
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
        ownerDisplayName: 'Ravi',
        ownerProfileId: 'ravi',
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
        ownerDisplayName: 'Ravi',
        ownerProfileId: 'ravi',
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
          ownerDisplayName: 'Ravi',
          ownerProfileId: 'ravi',
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
        ownerDisplayName: 'Ravi',
        ownerProfileId: 'ravi',
      );
      final report = await a.sync.syncGroup(created.group.id);
      expect(report.isClean, isTrue);
    });
  });
}
