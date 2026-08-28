import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/local_reset.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_conflict_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/data/sync/feeds.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import 'fake_remote_ledger.dart';

/// One simulated device: its own local database, outbox and sync engine, all
/// talking to a shared server.
class Device {
  Device(this.name, this._server, {this.profileId})
    : db = AppDatabase(NativeDatabase.memory()) {
    outbox = OutboxQueue(db);
    groups = DriftGroupRepository(db, outbox: outbox);
    entries = DriftEntryRepository(db, outbox: outbox);
    _engine = SyncEngine(db: db, api: _server, outbox: outbox);
  }

  final String name;
  final FakeRemoteLedger _server;

  /// The account this device holds a session for, if any.
  final String? profileId;

  final AppDatabase db;
  late final OutboxQueue outbox;
  late final DriftGroupRepository groups;
  late final DriftEntryRepository entries;
  late final SyncEngine _engine;

  /// The engine, with the server told whose session is making the request.
  ///
  /// Both devices share one [FakeRemoteLedger], as they share one server, so
  /// something has to say which of them is talking. Setting it here rather than
  /// at every call site keeps the 60-odd `a.sync.…` and `b.sync.…` lines
  /// reading as they did -- and it matters now, because authorship of an
  /// activity row is resolved by the server from the session rather than sent
  /// with the write.
  SyncEngine get sync {
    _server.actingProfileId = profileId;
    return _engine;
  }

  Future<void> close() => db.close();

  Future<List<Entry>> ledger(String groupId) =>
      entries.getEntries(groupId, includeDeleted: true);

  Future<List<EntryEvent>> feed(String groupId) =>
      DriftActivityRepository(db).watchGroup(groupId).first;
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
    a = Device('A', server, profileId: 'profile-ravi');
    // Priya is a placeholder in the shared fixture, so B holds a session that
    // is nobody's member row -- its writes are recorded with no actor, which is
    // exactly how the server treats a change it cannot attribute.
    b = Device('B', server, profileId: 'profile-priya');
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
    test(
      'a hung upload times out without dropping the pending write',
      () async {
        final g = await seedGroup();
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 100,
            description: 'Dinner',
            split: EqualSplit([g.ravi]),
            payerAmounts: {g.ravi: 100},
          ),
          createdBy: g.ravi,
        );
        final release = Completer<void>();
        server.beforeUpsertEntry = (_) => release.future;
        final engine = SyncEngine(
          db: a.db,
          api: server,
          outbox: a.outbox,
          requestTimeout: const Duration(milliseconds: 20),
        );

        final report = await engine.syncEverything();

        expect(report.failed, 1);
        expect(await a.outbox.pendingCount(), 1);
        release.complete();
      },
    );

    test(
      'sign-out fences responses already in flight and future background sync',
      () async {
        await seedGroup();
        await a.sync.syncEverything();
        final entered = Completer<void>();
        final release = Completer<void>();
        server.beforePullMyGroupIds = (_) async {
          entered.complete();
          await release.future;
        };
        final pending = a.sync.syncEverything();
        await entered.future;
        await forgetLocalLedger(a.db);
        release.complete();
        await pending;

        expect(await a.db.select(a.db.groups).get(), isEmpty);
        expect(await a.db.select(a.db.syncCursors).get(), isEmpty);
        final background = SyncEngine(db: a.db, api: server, outbox: a.outbox);
        expect((await background.syncEverything()).isClean, isFalse);
        expect(await a.db.select(a.db.groups).get(), isEmpty);
      },
    );

    test(
      'an edit during upload survives acknowledgement of the older edit',
      () async {
        final g = await seedGroup();
        EntryDraft draft(int amount) => EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: amount,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: amount},
        );
        final entry = await a.entries.create(draft(1000), createdBy: g.ravi);
        var edited = false;
        server.beforeUpsertEntry = (_) async {
          if (edited) return;
          edited = true;
          await a.entries.update(entry.id, draft(2500), actorId: g.ravi);
        };

        final report = await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        expect(report.isClean, isTrue, reason: '$report');
        expect(server.upsertCalls, 2);
        expect((await a.entries.getEntry(entry.id))!.amountMinor, 2500);
        expect((await b.entries.getEntry(entry.id))!.amountMinor, 2500);
        expect(await a.outbox.pendingCount(), 0);
      },
    );

    test(
      'pending edits survive pulls even with a clock behind the server',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 1000,
            description: 'Dinner',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 1000},
          ),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        final oldClock = DateTime.utc(2000);
        final localEntries = DriftEntryRepository(
          a.db,
          outbox: a.outbox,
          clock: () => oldClock,
        );
        await localEntries.update(
          entry.id,
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 3500,
            description: 'Edited offline',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 3500},
          ),
          actorId: g.ravi,
        );
        // Replay a page, as after a reconnect or a reset cursor.
        await a.db.delete(a.db.syncCursors).go();
        await a.sync.pull(g.groupId);

        expect((await a.entries.getEntry(entry.id))!.amountMinor, 3500);
        expect(await a.outbox.pendingCount(), 1);
      },
    );

    test('old failures cannot back off or remove a fresh edit', () async {
      await a.outbox.enqueue(OutboxTarget.group, 'queued-group');
      final old = (await a.outbox.due()).single;
      await a.outbox.enqueue(OutboxTarget.group, 'queued-group');

      await a.outbox.fail(
        old.id,
        'refused',
        permanent: true,
        revision: old.revision,
      );
      await a.outbox.complete(old.id, revision: old.revision);

      final current = (await a.outbox.due()).single;
      expect(current.revision, isNot(old.revision));
      expect(current.attempts, 0);
      expect(current.deadLetteredAt, isNull);
    });

    test(
      'separate engine instances serialize through the database lease',
      () async {
        await seedGroup();
        await a.sync.syncEverything();

        final entered = Completer<void>();
        final release = Completer<void>();
        server.pullMyGroupIdsCalls = 0;
        server.beforePullMyGroupIds = (call) async {
          if (call != 1) return;
          entered.complete();
          await release.future;
        };

        final otherEngine = SyncEngine(db: a.db, api: server, outbox: a.outbox);
        final first = a.sync.syncEverything();
        await entered.future;
        final second = otherEngine.syncEverything();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          server.pullMyGroupIdsCalls,
          1,
          reason: 'the second engine must not enter while the first owns lease',
        );

        release.complete();
        await Future.wait([first, second]);
        expect(server.pullMyGroupIdsCalls, 2);
      },
    );

    test('a new engine resumes after an abandoned lease expires', () async {
      server.signedInProfileId = 'profile-ravi';
      await b.db
          .into(b.db.syncLeases)
          .insert(
            SyncLeasesCompanion.insert(
              name: 'ledger',
              owner: 'closed-browser-tab',
              expiresAt: DateTime.now().toUtc().add(
                const Duration(milliseconds: 100),
              ),
            ),
          );

      final report = await b.sync.syncEverything();

      expect(report.isClean, isTrue, reason: '$report');
      expect(await b.db.select(b.db.syncLeases).get(), isEmpty);
    });

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
      expect(
        pushReport.pushed,
        5,
        reason:
            'group, 3 members and 1 entry. The feed line is not among them: '
            'the server writes history from the expense it commits, so there '
            'is nothing for a client to push',
      );

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

      await a.entries.delete(entry.id, actorId: g.ravi);
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

    test('a stale delete is parked instead of erasing a newer edit', () async {
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

      await a.entries.update(
        entry.id,
        actorId: g.ravi,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 200000,
          description: 'Corrected',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 200000},
        ),
      );
      await a.sync.syncGroup(g.groupId);

      await b.entries.delete(entry.id, actorId: g.priya);
      await b.sync.syncGroup(g.groupId);

      final current = (await b.ledger(g.groupId)).single;
      expect(current.isDeleted, isFalse);
      expect(current.amountMinor, 200000);

      final conflicts = await DriftConflictRepository(b.db).watchAll().first;
      expect(conflicts, hasLength(1));
      expect(conflicts.single.attempted.isDeleted, isTrue);
      expect(conflicts.single.current?.amountMinor, 200000);
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
        actorId: g.ravi,
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
        actorId: g.ravi,
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
        //
        // One row. A save used to queue two -- the expense and the line
        // describing it, which the server then refused in turn for naming an
        // entry it did not have -- so a single refused save produced two dead
        // letters and needed filtering before anybody could be told. The server
        // writes the history now, so there is only the expense.
        final dead = await a.outbox.deadLetters();
        expect(dead, hasLength(1));
        expect(
          dead.map((row) => row.lastError).join('\n'),
          contains('does not balance'),
        );

        final reported = await a.outbox.watchDeadLetters().first;
        expect(reported, hasLength(1));
        expect(reported.single.target, OutboxTarget.entry);
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
      expect(
        await a.outbox.pendingCount(),
        9,
        reason:
            'group + 3 members + 5 entries. Activity is not queued at '
            'all any more: the server writes it from the expense it commits',
      );

      await a.sync.syncGroup(g.groupId);
      expect(await a.outbox.pendingCount(), 0);

      await b.sync.syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), hasLength(5));
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
    });

    test('a queue longer than one page drains in a single sync', () async {
      // `due()` answers a bounded page, so a push that made a single pass left
      // the rest of the queue behind — and `pull` runs straight afterwards,
      // comparing those un-pushed rows, which still carry a device clock,
      // against the server's own timestamps.
      final g = await seedGroup();
      const count = 120;
      for (var i = 0; i < count; i++) {
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 10000 + i,
            description: 'Offline $i',
            split: EqualSplit([g.ravi, g.priya]),
            payerAmounts: {g.ravi: 10000 + i},
          ),
          createdBy: g.ravi,
        );
      }

      // Comfortably more than the 100 rows one `due()` page can return.
      expect(await a.outbox.pendingCount(), count + 4);

      final report = await a.sync.syncGroup(g.groupId);
      expect(report.failed, 0);
      expect(
        await a.outbox.pendingCount(),
        0,
        reason: 'one sync should leave nothing queued',
      );

      await b.sync.syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), hasLength(count));
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
    test(
      'a failed cursor write rolls back its page and can be retried',
      () async {
        final group = await seedGroup();
        server.signedInProfileId = 'profile-ravi';
        expect((await a.sync.syncEverything()).isClean, isTrue);
        await b.db.customStatement('''
        CREATE TRIGGER reject_member_cursor BEFORE INSERT ON sync_cursors
        WHEN NEW.feed LIKE 'members:%'
        BEGIN SELECT RAISE(ABORT, 'test cursor failure'); END;
      ''');

        final failed = await b.sync.syncEverything();
        expect(failed.isClean, isFalse);
        expect(await b.db.select(b.db.members).get(), isEmpty);
        expect(
          await (b.db.select(
            b.db.syncCursors,
          )..where((row) => row.feed.equals('members:${group.groupId}'))).get(),
          isEmpty,
        );

        await b.db.customStatement('DROP TRIGGER reject_member_cursor');
        expect((await b.sync.syncEverything()).isClean, isTrue);
        expect(await b.db.select(b.db.members).get(), hasLength(3));
      },
    );

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

    test('failed discovery is not a successful local-only answer', () async {
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      server.beforePullMyGroupIds = (_) async => throw StateError('offline');
      await expectLater(a.sync.discoverGroups(), throwsStateError);
      expect(
        (await a.db.select(a.db.groups).get()).single.id,
        created.group.id,
      );
      expect(await a.outbox.pendingCount(), greaterThan(0));
    });

    test(
      'an empty device reports a discovery failure and can recover',
      () async {
        server.signedInProfileId = 'profile-ravi';
        server.beforePullMyGroupIds = (_) async =>
            throw StateError('unreachable');

        final failed = await b.sync.syncEverything();

        expect(failed.isClean, isFalse);
        expect(failed.error, isA<StateError>());
        expect(await b.db.select(b.db.groups).get(), isEmpty);

        server.beforePullMyGroupIds = null;
        expect((await b.sync.syncEverything()).isClean, isTrue);
      },
    );
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
        groupId: created.group.id,
        limit: 500,
      )).rows.firstWhere((m) => m.id == priya.id);
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

      await engine.drain(ProfileFeed(server, db));
      final first = await DriftProfileRepository(db).byId('priya-account');
      expect(first?.displayName, 'Priya');

      // She renames herself on her own phone. Nothing about any group changes
      // — which is the point: the name is not copied into a member row per
      // group any more, so this is one write reaching everybody.
      server.seedProfile(
        const Profile(id: 'priya-account', displayName: 'Priya S'),
      );

      await engine.drain(ProfileFeed(server, db));
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

      await engine.drain(ProfileFeed(server, db));
      expect(
        server.lastProfilesSince,
        isNull,
        reason: 'the first pull holds nothing, so it asks for everything',
      );

      await engine.drain(ProfileFeed(server, db));
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

  group('the activity feed', () {
    test('is written locally, with no server in sight', () async {
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 120000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 120000},
        ),
        createdBy: g.ravi,
      );

      // No sync has run. This is the whole point of the redesign: the feed
      // used to be written by a trigger on the server, so until a push
      // succeeded there was nothing here at all — and for a guest whose
      // backend was unreachable, there never would be.
      final feed = await a.feed(g.groupId);
      expect(feed, hasLength(1));
      expect(feed.single.kind, EntryEventKind.created);
      expect(feed.single.actorId, g.ravi);
    });

    test('reaches the other device, once and only once', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 120000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 120000},
        ),
        createdBy: g.ravi,
      );
      await a.entries.update(
        entry.id,
        actorId: g.ravi,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
      );

      // Before syncing, A has its own account of both writes.
      expect((await a.feed(g.groupId)).map((e) => e.kind), [
        EntryEventKind.edited,
        EntryEventKind.created,
      ], reason: 'provisional, but on screen the moment each save happened');

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      // One line, on both devices, and that is correct rather than lossy.
      //
      // The outbox coalesces by row, so an expense created and then edited
      // before any sync reaches the server once, as its final state -- and the
      // server records what it committed. "Ravi added this, for Rs.1,000" is a
      // true account of what happened; the Rs.1,200 that existed only on A's
      // screen for a moment was never a fact about the group.
      //
      // A's provisional pair is superseded rather than kept alongside, so the
      // two devices agree.
      expect((await b.feed(g.groupId)).map((e) => e.kind), [
        EntryEventKind.created,
      ]);
      expect((await a.feed(g.groupId)).map((e) => e.kind), [
        EntryEventKind.created,
      ]);
      expect(
        (await a.feed(g.groupId)).single.isProvisional,
        isFalse,
        reason: 'the server\'s account replaced this device\'s guess',
      );

      // Syncing again must not duplicate anything.
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      expect(await a.feed(g.groupId), hasLength(1));
      expect(await b.feed(g.groupId), hasLength(1));
    });

    test('an edit the server witnesses separately is its own line', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 120000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 120000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);

      await a.entries.update(
        entry.id,
        actorId: g.ravi,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 100000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 100000},
        ),
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      final feed = await b.feed(g.groupId);
      expect(feed.map((e) => e.kind), [
        EntryEventKind.edited,
        EntryEventKind.created,
      ], reason: 'newest first');

      // The point of the whole feature: what actually changed, in money.
      final amount = feed.first.changes.singleWhere(
        (c) => c.field == 'amount_minor',
      );
      expect(amount.from, '120000');
      expect(amount.to, '100000');
      expect(
        feed.first.actorId,
        g.ravi,
        reason:
            'resolved by the server from the session, not sent with the '
            'write',
      );
    });

    test('a re-split is recorded even though the total never moves', () async {
      // The edit this redesign exists for. Priya owes Rs.300 of the Rs.400
      // dinner instead of Rs.200; the total is untouched, so the balance
      // invariant is satisfied and nothing about the expense looks different.
      final g = await seedGroup();
      final entry = await a.entries.create(
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
      await a.sync.syncGroup(g.groupId);

      await a.entries.update(
        entry.id,
        actorId: g.ravi,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 40000,
          description: 'Dinner',
          split: ExactSplit({g.ravi: 10000, g.priya: 30000}),
          payerAmounts: {g.ravi: 40000},
        ),
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      final latest = (await b.feed(g.groupId)).first;
      expect(latest.kind, EntryEventKind.edited);
      expect(
        latest.changes.map((c) => c.field),
        containsAll(['share:${g.ravi}', 'share:${g.priya}']),
        reason:
            'who owes what is where the money lives, and a history that '
            'recorded only the total could not see this at all',
      );
      expect(
        latest.changes.singleWhere((c) => c.field == 'share:${g.priya}').to,
        '30000',
      );
    });

    test('is not skipped when a device stamps its own clock ahead', () async {
      final g = await seedGroup();
      await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 120000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.ravi: 120000},
        ),
        createdBy: g.ravi,
      );

      // A's provisional snapshot carries A's clock, which here is a year fast.
      // It is never pushed, and the activity cursor is its own row fed only by
      // server timestamps -- so this must not move any cursor at all. Read off
      // the local table instead, as it once was, and A would set its own cursor
      // into the future and never see another line of this group's history
      // from anybody.
      await (a.db.update(a.db.entrySnapshots)).write(
        EntrySnapshotsCompanion(createdAt: Value(DateTime.utc(2027, 8, 21))),
      );

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      expect(await b.feed(g.groupId), hasLength(1));

      await b.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 60000,
          description: 'Taxi',
          split: EqualSplit([g.ravi, g.priya]),
          payerAmounts: {g.priya: 60000},
        ),
        createdBy: g.priya,
      );
      await b.sync.syncGroup(g.groupId);
      await a.sync.syncGroup(g.groupId);

      expect(
        await a.feed(g.groupId),
        hasLength(2),
        reason:
            'the server owns the clock, so a device with a wrong one '
            'cannot push everybody else past what it has not read',
      );
    });
  });

  group('an edit overtaken by somebody else', () {
    /// Ravi and Priya both hold the expense, then both edit it. Priya's push
    /// lands first, so Ravi's is composed against a version that no longer
    /// exists.
    Future<
      ({String groupId, String entryId, String ravi, String priya, String arun})
    >
    divergent({
      required int raviAmount,
      required String raviDescription,
      required int priyaAmount,
    }) async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 30000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: 30000},
        ),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      // B edits and pushes. A never hears about it -- it is offline, or simply
      // has not synced since.
      await b.entries.update(
        entry.id,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: priyaAmount,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: priyaAmount},
        ),
        actorId: g.priya,
      );
      await b.sync.syncGroup(g.groupId);

      // A edits the copy it still believes in.
      await a.entries.update(
        entry.id,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: raviAmount,
          description: raviDescription,
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: raviAmount},
        ),
        actorId: g.ravi,
      );

      return (
        groupId: g.groupId,
        entryId: entry.id,
        ravi: g.ravi,
        priya: g.priya,
        arun: g.arun,
      );
    }

    test('the ledger converges and the edit is kept', () async {
      final g = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );

      await a.sync.syncGroup(g.groupId);

      // The money follows the server. The alternative -- holding this device's
      // version until somebody decides -- leaves A reading balances nobody
      // else in the group agrees with, for as long as nobody notices.
      final onA = (await a.ledger(g.groupId)).single;
      expect(
        onA.amountMinor,
        45000,
        reason:
            "A converged on the group's version rather than keeping its "
            'own and splitting the group over one expense',
      );

      final conflicts = await DriftConflictRepository(a.db).watchAll().first;
      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.attempted.amountMinor,
        60000,
        reason: 'and what A meant is kept, because it is the only copy left',
      );
      expect(
        conflicts.single.current?.amountMinor,
        45000,
        reason:
            'alongside what the group has, which is what makes the two '
            'numbers together enough to settle it without a dialog',
      );
    });

    test('it does not sit in the outbox being refused forever', () async {
      final g = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );

      await a.sync.syncGroup(g.groupId);

      expect(
        await a.outbox.pendingCount(),
        0,
        reason: 'resending the same stale base is refused identically forever',
      );
      expect(
        await a.outbox.deadLetters(),
        isEmpty,
        reason:
            'and it is not a dead letter either: a dead letter says nobody '
            'can see this, which is exactly wrong -- everybody can see the '
            'expense, just not this edit to it',
      );
    });

    test('an edit that moves no money is simply applied', () async {
      final g = await divergent(
        raviAmount: 45000,
        raviDescription: 'Dinner at Toit',
        priyaAmount: 45000,
      );

      await a.sync.syncGroup(g.groupId);

      // A's edit was composed against a version B had already replaced, but it
      // carries B's amount, so applying it moves nothing. Arbitrating that
      // would cost two people a decision to settle a typo.
      expect(await DriftConflictRepository(a.db).watchAll().first, isEmpty);
      expect((await a.ledger(g.groupId)).single.description, 'Dinner at Toit');

      await b.sync.syncGroup(g.groupId);
      expect((await b.ledger(g.groupId)).single.description, 'Dinner at Toit');
    });

    test('editing it again lands, and clears the notice', () async {
      final g = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      final conflicts = DriftConflictRepository(a.db);
      expect(await conflicts.byEntry(g.entryId), isNotNull);

      // The ordinary edit path, which is the only way there is. It is composed
      // against what the server holds now -- put there by the pull that
      // followed the rejection -- so it is an ordinary edit and lands. Being
      // refused a second time would mean the base never moved off the version
      // that was overtaken.
      await a.entries.update(
        g.entryId,
        EntryDraft(
          groupId: g.groupId,
          currency: 'INR',
          amountMinor: 60000,
          description: 'Dinner',
          split: EqualSplit([g.ravi, g.priya, g.arun]),
          payerAmounts: {g.ravi: 60000},
        ),
        actorId: g.ravi,
      );

      expect(
        await conflicts.byEntry(g.entryId),
        isNull,
        reason:
            'editing the expense is the acknowledgement: they have seen '
            'what it says and acted, so the banner has nothing left to ask',
      );

      await a.sync.syncGroup(g.groupId);
      expect((await a.ledger(g.groupId)).single.amountMinor, 60000);
      await b.sync.syncGroup(g.groupId);
      expect(
        (await b.ledger(g.groupId)).single.amountMinor,
        60000,
        reason: 'and it reaches the rest of the group like any other edit',
      );
    });

    test('the feed records both versions, in order', () async {
      final g = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      final feed = await a.feed(g.groupId);
      expect(
        feed.any((line) => line.kind == EntryEventKind.edited),
        isTrue,
        reason:
            "B's edit is on the record, attributed to B, even though A "
            'never saw it happen',
      );
    });
  });

  group('one engine, five feeds', () {
    /// A third device, holding nothing, to pull onto.
    Device freshDevice() {
      final device = Device('paged', server, profileId: 'profile-arun');
      addTearDown(device.close);
      return device;
    }

    Future<void> addExpenses(
      ({String groupId, String ravi, String priya, String arun}) g,
      int count,
    ) async {
      for (var i = 0; i < count; i++) {
        await a.entries.create(
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 30000,
            description: 'Dinner $i',
            split: EqualSplit([g.ravi, g.priya, g.arun]),
            payerAmounts: {g.ravi: 30000},
          ),
          createdBy: g.ravi,
        );
      }
    }

    test('a feed that spans several pages arrives whole', () async {
      final g = await seedGroup();
      await addExpenses(g, 5);
      await a.sync.syncGroup(g.groupId);

      final device = freshDevice();
      final engine = SyncEngine(
        db: device.db,
        api: server,
        outbox: device.outbox,
        pageSize: 2,
      );
      await engine.pullShared();
      await engine.pull(g.groupId);

      expect(
        (await device.entries.getEntries(g.groupId)).length,
        5,
        reason:
            'five rows in pages of two: the cursor has to advance across a '
            'boundary four times without losing or repeating a row',
      );
      expect(
        (await DriftActivityRepository(
          device.db,
        ).watchGroup(g.groupId).first).length,
        5,
        reason: 'the activity feed pages on (created_at, id) the same way',
      );
    });

    test('rows sharing a timestamp survive a page boundary', () async {
      final g = await seedGroup();
      await addExpenses(g, 3);
      await a.sync.syncGroup(g.groupId);

      // Postgres now() is transaction time, so a batch written in one
      // transaction shares an updated_at exactly. A cursor on the timestamp
      // alone either skips the rest of that batch forever or re-reads it
      // forever; the pair terminates and loses nothing. Three rows at one
      // instant, read two at a time, puts the tie right on the boundary.
      final ledger = await a.ledger(g.groupId);
      await server.inOneTransaction(() async {
        for (final entry in ledger) {
          await server.upsertEntry(
            entry.copyWith(description: '${entry.description} (revised)'),
          );
        }
      });

      final device = freshDevice();
      final engine = SyncEngine(
        db: device.db,
        api: server,
        outbox: device.outbox,
        pageSize: 2,
      );
      await engine.pullShared();
      await engine.pull(g.groupId);

      final pulled = await device.entries.getEntries(g.groupId);
      expect(pulled, hasLength(3));
      expect(
        pulled.every((entry) => entry.description.endsWith('(revised)')),
        isTrue,
        reason: 'every row of the tied batch arrived, not just the first page',
      );
    });

    test('a settled feed costs an empty answer, not a refetch', () async {
      final g = await seedGroup();
      await addExpenses(g, 1);
      await a.sync.syncGroup(g.groupId);

      final device = freshDevice();
      await device.sync.syncGroup(g.groupId);

      // Members used to be refetched whole on every sync, with a SELECT per
      // row to decide whether to keep them. Syncs are frequent now that every
      // write triggers one, so "the group has not changed" has to be cheap.
      final second = await device.sync.syncGroup(g.groupId);
      expect(
        second.pulled,
        0,
        reason: 'nothing changed on the server, so nothing should be applied',
      );
    });
  });

  group('the outbox is a set of dirty rows, not a log', () {
    test(
      'backed-off parents block dependants until the retry is due',
      () async {
        var now = DateTime.utc(2026, 8, 28);
        final outbox = OutboxQueue(a.db, clock: () => now);
        addTearDown(outbox.dispose);
        await outbox.enqueue(OutboxTarget.group, 'g1');
        await outbox.enqueue(OutboxTarget.member, 'm1');
        await outbox.enqueue(OutboxTarget.entry, 'e1');
        await outbox.fail(
          OutboxQueue.idFor(OutboxTarget.group, 'g1'),
          'offline',
        );

        // The member and entry have no deadline, but cannot overtake the group.
        expect(await outbox.due(), isEmpty);
        expect(
          await outbox.nextAttemptAt(),
          now.add(const Duration(seconds: 2)),
        );

        now = now.add(const Duration(seconds: 2));
        expect((await outbox.due()).map((row) => row.targetId), [
          'g1',
          'm1',
          'e1',
        ]);
        await outbox.complete(OutboxQueue.idFor(OutboxTarget.group, 'g1'));
        await outbox.fail(
          OutboxQueue.idFor(OutboxTarget.member, 'm1'),
          'offline',
        );
        expect(await outbox.due(), isEmpty);

        now = now.add(const Duration(seconds: 2));
        expect((await outbox.due()).map((row) => row.targetId), ['m1', 'e1']);
      },
    );

    test('dead letters have no automatic retry deadline', () async {
      await a.outbox.enqueue(OutboxTarget.group, 'g1');
      expect(await a.outbox.nextAttemptAt(), isNotNull);
      await a.outbox.fail(
        OutboxQueue.idFor(OutboxTarget.group, 'g1'),
        'refused',
        permanent: true,
      );
      expect(await a.outbox.nextAttemptAt(), isNull);
    });

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

    test('every enqueue announces itself', () async {
      final outbox = OutboxQueue(a.db);
      addTearDown(outbox.dispose);

      final announced = <void>[];
      final subscription = outbox.queued.listen(announced.add);
      addTearDown(subscription.cancel);

      await outbox.enqueue(OutboxTarget.entry, 'e1');
      await outbox.enqueue(OutboxTarget.group, 'g1');
      await pumpEventQueue();

      // The other half of the wire that makes saving an expense reach the
      // group. Every mutation in the app funnels through enqueue, so this is
      // what covers screens nobody has written yet -- and what stops the fix
      // being a sync call at each save site, one of which will be forgotten.
      expect(announced, hasLength(2));
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
