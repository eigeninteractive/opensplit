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
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

import 'fake_remote_ledger.dart';

import '../harness.dart';

/// One simulated device: its own local database, outbox and sync engine, all
/// talking to a shared server.
class Device {
  /// The reference data a real device has by the time it can do anything.
  ///
  /// Seeded here rather than at each of the eleven call sites, and awaited
  /// through [ready]. A real device gets these on its first sweep and cannot
  /// create a group until it has -- `groups.default_currency` references
  /// `currencies` -- so a fake one that skipped them would be testing a state
  /// no device is ever in.
  late final Future<void> ready;

  Device(this.name, this._server, {this.profileId})
    : db = AppDatabase(NativeDatabase.memory()) {
    ready = seedReferenceData(db);
    outbox = OutboxQueue(db);
    groups = DriftGroupRepository(db, outbox: outbox);
    entries = DriftEntryRepository(db, outbox: outbox);
    _engine = SyncEngine(db: db, remote: _server, outbox: outbox);
  }

  final String name;
  final FakeRemoteLedger _server;

  /// The account this device holds a session for, if any.
  ///
  /// Mutable, because signing in as somebody else is a thing devices do and
  /// several tests turn on it -- a second device belonging to the same person
  /// is the case that discovery exists for.
  String? profileId;

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
    if (profileId != null) _server.profileId = profileId!;
    return _engine;
  }

  Future<void> close() => db.close();

  Future<List<Entry>> ledger(String groupId) =>
      entries.getEntries(groupId, includeDeleted: true);

  /// The expense half of the record.
  ///
  /// Narrowed rather than returning every kind, because everything these tests
  /// assert about the feed is about expenses -- and the fake server only ever
  /// records those, since member and group events come from database triggers
  /// that have no counterpart here. A member event appearing in these results
  /// would be the fake inventing one.
  Future<List<EntryChanged>> feed(String groupId) async =>
      (await DriftActivityRepository(
        db,
      ).watchGroup(groupId).first).whereType<EntryChanged>().toList();
}

void main() {
  group('reference data', () {
    test('a currency added on the server reaches a device', () async {
      // The point of syncing these at all. The app ships with a preset list so
      // it can format an amount before it has ever reached the network, but a
      // seed is a floor rather than a source -- without this, adding a currency
      // meant shipping a release for a row.
      final server = FakeRemoteLedger();
      final device = Device('solo', server);
      await device.ready;
      addTearDown(device.close);

      server.serverCurrencies.add(
        api.Currency(code: 'XCD', exponent: 2, symbol: r'$', name: 'Test'),
      );
      await device.sync.syncEverything();

      final held = await device.db.select(device.db.currencies).get();
      expect(
        held.map((c) => c.code),
        contains('XCD'),
        reason: 'no app update required',
      );
    });

    test('a currency withdrawn on the server stays on the device', () async {
      // Upsert, never delete. A category or currency taken off the server is
      // still on the expenses that used it, and entries.category_id references
      // it -- removing the row to tidy a list would break a foreign key.
      final server = FakeRemoteLedger();
      final device = Device('solo', server);
      await device.ready;
      addTearDown(device.close);

      server.serverCurrencies.removeWhere((c) => c.code == 'INR');
      await device.sync.syncEverything();

      final held = await device.db.select(device.db.currencies).get();
      expect(held.map((c) => c.code), contains('INR'));
    });

    test('a renamed currency is corrected in place', () async {
      final server = FakeRemoteLedger();
      final device = Device('solo', server);
      await device.ready;
      addTearDown(device.close);

      final inr = server.serverCurrencies.firstWhere((c) => c.code == 'INR');
      server.serverCurrencies
        ..remove(inr)
        ..add(
          api.Currency(
            code: inr.code,
            exponent: inr.exponent,
            symbol: inr.symbol,
            name: 'Indian Rupee (renamed)',
          ),
        );
      await device.sync.syncEverything();

      final held = await (device.db.select(
        device.db.currencies,
      )..where((t) => t.code.equals('INR'))).getSingle();
      expect(held.name, 'Indian Rupee (renamed)');
    });
  });

  // Two devices means two AppDatabase instances in one process. They are
  // separate in-memory databases, so the usual warning does not apply.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeRemoteLedger server;
  late Device a;
  late Device b;

  setUp(() async {
    server = FakeRemoteLedger();
    a = Device('A', server, profileId: 'profile-ravi');
    await a.ready;
    // Priya is a placeholder in the shared fixture, so B holds a session that
    // is nobody's member row -- its writes are recorded with no actor, which is
    // exactly how the server treats a change it cannot attribute.
    b = Device('B', server, profileId: 'profile-priya');
    await b.ready;
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
          remote: server,
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
        server.beforeBootstrap = (_) async {
          entered.complete();
          await release.future;
        };
        final pending = a.sync.syncEverything();
        await entered.future;
        await forgetLocalLedger(a.db);
        release.complete();
        await pending;

        expect(await a.db.select(a.db.groups).get(), isEmpty);
        expect(await a.db.select(a.db.groupCursors).get(), isEmpty);
        final background = SyncEngine(
          db: a.db,
          remote: server,
          outbox: a.outbox,
        );
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
        await a.db.delete(a.db.groupCursors).go();
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
        server.bootstrapCalls = 0;
        server.beforeBootstrap = (call) async {
          if (call != 1) return;
          entered.complete();
          await release.future;
        };

        final otherEngine = SyncEngine(
          db: a.db,
          remote: server,
          outbox: a.outbox,
        );
        final first = a.sync.syncEverything();
        await entered.future;
        final second = otherEngine.syncEverything();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          server.bootstrapCalls,
          1,
          reason: 'the second engine must not enter while the first owns lease',
        );

        release.complete();
        await Future.wait([first, second]);
        expect(server.bootstrapCalls, 2);
      },
    );

    test('a new engine resumes after an abandoned lease expires', () async {
      b.profileId = 'profile-ravi';
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
      expect(conflicts.single.attempted.deletedAt, isNotNull);
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
          contains('does not add up'),
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
      expect(failures.single.reason, contains('does not add up'));
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
        remote: server,
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

    test('gives every committed change a number of its own', () async {
      // The property a timestamp cursor cannot have. Rows written together
      // can share a timestamp exactly, and a cursor on one either skips the
      // rest of that batch forever or re-reads it forever -- which is why such
      // a cursor needs a tiebreak column at all.
      //
      // A sequence number is issued once per committed change by the one
      // writer there is, so the tie cannot arise. Twelve pushes are twelve
      // numbers, strictly increasing, whatever order they drain in.
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
      await a.sync.push();

      final stamps = [for (final e in await a.ledger(g.groupId)) e.seq!]
        ..sort();
      expect(stamps.toSet(), hasLength(12), reason: 'no number is reused');
      expect(
        stamps,
        orderedEquals([for (var i = 0; i < 12; i++) stamps.first + i]),
        reason: 'and none is skipped, so a cursor cannot step over a change',
      );

      final small = SyncEngine(
        db: b.db,
        remote: server,
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
        [
          OutboxTarget.group,
          OutboxTarget.member,
          OutboxTarget.member,
          OutboxTarget.member,
          OutboxTarget.entry,
        ],
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

    test('reaches back for a day a backdated expense needs', () async {
      // The case a high-water mark structurally cannot serve, and the reason
      // `requestFxBackfill` is not decorative: the rate is older than anything
      // this device holds, so a pull anchored to the newest date would never
      // mention it however many times the server fetched it.
      server.publishFxRate(asOf: '2026-08-20', currency: 'USD', rate: 1);

      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      await a.sync.syncGroup(created.group.id);
      expect(server.lastFxSince, isNot('2024-03-11'));

      // Backdated, and in a currency that is not the group's own — a bill in
      // the group's own currency is never converted and needs no rate.
      await a.entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'USD',
          amountMinor: 4200,
          description: 'Last year',
          entryDate: DateTime.utc(2024, 3, 11),
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 4200},
        ),
        createdBy: created.creator.id,
      );
      server.publishFxRate(asOf: '2024-03-11', currency: 'USD', rate: 1);

      await a.sync.syncGroup(created.group.id);
      expect(server.lastFxSince, '2024-03-11');
      expect(
        (await a.db.select(a.db.fxRates).get()).map((row) => row.asOf),
        contains('2024-03-11'),
      );
    });

    test('widens the window once, not on every sync forever', () async {
      // A date no provider will ever answer — before their history begins —
      // would otherwise make every sync ask for the whole window again and
      // write back the same thousands of rows it already had.
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'ravi',
      );
      await a.entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: 'USD',
          amountMinor: 4200,
          description: 'Long ago',
          entryDate: DateTime.utc(1999, 1, 1),
          split: EqualSplit([created.creator.id]),
          payerAmounts: {created.creator.id: 4200},
        ),
        createdBy: created.creator.id,
      );

      await a.sync.syncGroup(created.group.id);
      expect(server.lastFxSince, '1999-01-01');

      server.lastFxSince = null;
      await a.sync.syncGroup(created.group.id);
      expect(
        server.lastFxSince,
        isNot('1999-01-01'),
        reason: 'the floor records how far back it has already reached',
      );
    });

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
        b.profileId = 'profile-ravi';
        await a.entries.create(
          EntryDraft(
            groupId: group.groupId,
            currency: 'INR',
            amountMinor: 90000,
            description: 'Dinner',
            split: EqualSplit([group.ravi, group.priya]),
            payerAmounts: {group.ravi: 90000},
          ),
          createdBy: group.ravi,
        );
        expect((await a.sync.syncEverything()).isClean, isTrue);

        // There is one cursor per group now rather than one per feed, which
        // makes this a sharper question than it used to be: a page is the
        // group row, its members, its expenses and its activity applied
        // together, so a cursor that cannot be written has to take all of them
        // back. Half a page plus no cursor is the state that re-reads forever.
        await b.db.customStatement('''
        CREATE TRIGGER reject_group_cursor BEFORE INSERT ON group_cursors
        BEGIN SELECT RAISE(ABORT, 'test cursor failure'); END;
      ''');

        final failed = await b.sync.syncEverything();
        expect(failed.isClean, isFalse);
        expect(await b.db.select(b.db.members).get(), isEmpty);
        expect(await b.db.select(b.db.entries).get(), isEmpty);
        expect(await b.db.select(b.db.groupEvents).get(), isEmpty);
        expect(await b.db.select(b.db.groupCursors).get(), isEmpty);

        await b.db.customStatement('DROP TRIGGER reject_group_cursor');
        expect((await b.sync.syncEverything()).isClean, isTrue);
        expect(await b.db.select(b.db.members).get(), hasLength(3));
        expect(await b.ledger(group.groupId), hasLength(1));
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
      b.profileId = 'profile-ravi';
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

      b.profileId = 'profile-ravi';
      expect(await b.sync.discoverGroups(), isEmpty);
    });

    test('failed discovery is not a successful local-only answer', () async {
      final created = await a.groups.createGroup(
        name: 'Goa Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: 'profile-ravi',
      );
      server.beforeBootstrap = (_) async => throw StateError('offline');
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
        b.profileId = 'profile-ravi';
        server.beforeBootstrap = (_) async => throw StateError('unreachable');

        final failed = await b.sync.syncEverything();

        expect(failed.isClean, isFalse);
        expect(failed.error, isA<StateError>());
        expect(await b.db.select(b.db.groups).get(), isEmpty);

        server.beforeBootstrap = null;
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

      // Priya claims her place on the server, as joining by link would.
      server.claimMember(created.group.id, priya.id, 'profile-priya');

      // Device A still believes she is a placeholder, and renames her.
      await a.groups.renameMember(priya.id, 'Priya S');
      await a.sync.syncGroup(created.group.id);

      // The server's own view, read before anything else touches it: the
      // rename has to have landed, and the claim has to have survived it.
      final onServer = server.memberOn(created.group.id, priya.id);
      expect(onServer.displayName, 'Priya S', reason: 'the rename still lands');
      expect(
        onServer.profileId,
        'profile-priya',
        reason:
            'the push carried a stale profile_id of null and un-joined the '
            'person who had just claimed their invite',
      );

      // And she can therefore still find the group from a device of her own.
      b.profileId = 'profile-priya';
      expect(await b.sync.discoverGroups(), [created.group.id]);
    });
  });

  group('a name follows the account, not the group', () {
    test(
      'an invite claim hydrates a profile older than the feed cursor',
      () async {
        final created = await a.groups.createGroup(
          name: 'Goa Trip',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Ravi',
          creatorProfileId: 'profile-ravi',
        );
        final priya = await a.groups.addMember(
          created.group.id,
          displayName: 'Priya placeholder',
        );
        await a.sync.syncGroup(created.group.id);

        // Priya's Google account existed before this device could see it. A
        // later visible profile moves the account-wide cursor beyond hers.
        server.seedProfile(
          const Profile(id: 'profile-priya', displayName: 'Priya D'),
        );
        server.seedProfile(
          const Profile(id: 'profile-later', displayName: 'Later profile'),
        );
        await a.sync.pullShared();
        await (a.db.delete(
          a.db.profiles,
        )..where((t) => t.id.equals('profile-priya'))).go();

        // Redeeming the invite changes the member, not an already-named Google
        // profile. The incremental profile feed therefore cannot see Priya
        // behind its cursor; the member claim must hydrate her exact row.
        server.claimMember(created.group.id, priya.id, 'profile-priya');
        await a.sync.syncGroup(created.group.id);

        final profile = await DriftProfileRepository(
          a.db,
        ).byId('profile-priya');
        expect(profile?.displayName, 'Priya D');
      },
    );

    test('a rename by somebody else arrives on the next sync', () async {
      final server = FakeRemoteLedger();
      final db = AppDatabase(NativeDatabase.memory());
      await seedReferenceData(db);
      addTearDown(db.close);
      final engine = SyncEngine(
        db: db,
        remote: server,
        outbox: OutboxQueue(db),
      );

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
      await seedReferenceData(db);
      addTearDown(db.close);
      final engine = SyncEngine(
        db: db,
        remote: server,
        outbox: OutboxQueue(db),
      );

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
      await (a.db.update(a.db.groupEvents)).write(
        GroupEventsCompanion(createdAt: Value(DateTime.utc(2027, 8, 21))),
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

    test(
      'converges even when a pull skipped the newer version first',
      () async {
        final g = await divergent(
          raviAmount: 60000,
          raviDescription: 'Dinner',
          priyaAmount: 45000,
        );

        // A's push fails once, but the pull in the same run still happens. It
        // skips the server's newer row, because A's edit is still queued, and
        // moves the cursor past it.
        var failOnce = true;
        server.beforeUpsertEntry = (_) async {
          if (failOnce) {
            failOnce = false;
            throw const ApiFailure('blip', retry: api.Retry.transient);
          }
        };
        await a.sync.syncGroup(g.groupId);
        await a.db
            .update(a.db.outbox)
            .write(const OutboxCompanion(nextAttemptAt: Value(null)));

        // Refused as stale, parked, and the server's version read again.
        await a.sync.syncGroup(g.groupId);

        expect((await a.ledger(g.groupId)).single.amountMinor, 45000);
        final conflict = (await DriftConflictRepository(
          a.db,
        ).watchAll().first).single;
        expect(conflict.attempted.amountMinor, 60000);
        expect(conflict.current?.amountMinor, 45000);
      },
    );

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

  group('one engine, one feed', () {
    /// A third device, holding nothing, to pull onto.
    Future<Device> freshDevice() async {
      final device = Device('paged', server, profileId: 'profile-arun');
      await device.ready;
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

      final device = await freshDevice();
      final engine = SyncEngine(
        db: device.db,
        remote: server,
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
        reason:
            'the activity feed rides the same cursor -- it is not a feed of '
            'its own any more, so it cannot page differently or lag behind',
      );
    });

    test('a page is never cut inside one change', () async {
      final g = await seedGroup();
      await a.sync.syncGroup(g.groupId);
      // Where the group's own setup ends, so the next page starts at the first
      // expense rather than at the group row and its members.
      final beforeExpenses = server.seqOf(g.groupId);

      await addExpenses(g, 3);
      await a.sync.syncGroup(g.groupId);

      // The invariant that replaced the composite cursor, and the one thing a
      // single integer has to get right. A `limit` counts changes, not rows: a
      // save writes an expense and the activity line describing it under one
      // sequence number, and both cross the wire together or neither does.
      //
      // Cutting by rows instead would let a device hold an expense whose
      // record had not arrived -- or, with payers and shares on the same
      // number, an amount that does not add up on somebody's screen.
      final firstPage = await server.changes(
        g.groupId,
        since: beforeExpenses,
        limit: 1,
      );
      expect(firstPage.entries, hasLength(1));
      expect(firstPage.events.map((event) => event.seq), [
        firstPage.entries.single.seq,
      ], reason: 'the expense and its record share a number and a page');
      expect(firstPage.hasMore, isTrue);

      final device = await freshDevice();
      final engine = SyncEngine(
        db: device.db,
        remote: server,
        outbox: device.outbox,
        pageSize: 1,
      );
      await engine.pullShared();
      await engine.pull(g.groupId);

      expect(await device.entries.getEntries(g.groupId), hasLength(3));
      expect(
        (await DriftActivityRepository(
          device.db,
        ).watchGroup(g.groupId).first).length,
        3,
        reason: 'one change per page, four boundaries, nothing lost or doubled',
      );
    });

    test('a settled feed costs an empty answer, not a refetch', () async {
      final g = await seedGroup();
      await addExpenses(g, 1);
      await a.sync.syncGroup(g.groupId);

      final device = await freshDevice();
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
