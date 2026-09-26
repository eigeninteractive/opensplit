@Tags(['integration'])
library;

import 'dart:async';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, Value, driftRuntimeOptions;
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/local_reset.dart';
import 'package:opensplit/data/repositories/drift_conflict_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/domain/balance/balance_fold.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

import 'live_backend.dart';

/// The sync algorithm, end to end: devices with their own databases, talking
/// to a real local Worker.
typedef Seed = ({String groupId, String ravi, String priya, String arun});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpBackend();

  late Device a;
  late Device b;

  /// Ravi on device A, and a second person on device B.
  Future<void> start() async {
    a = await Device.guest();
    b = await Device.guest();
  }

  /// A pushes the group; B claims Priya and pulls it.
  Future<void> join(Seed g) async {
    await a.sync.syncGroup(g.groupId);
    await b.claim(a, g.groupId, g.priya);
    await b.sync.syncGroup(g.groupId);
  }

  /// A group on A with Ravi, Priya and Arun. With [joined], A pushes it and B
  /// claims Priya's place and pulls it.
  Future<Seed> seedGroup({bool joined = true}) async {
    await start();
    final created = await a.groups.createGroup(
      name: 'Goa Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: a.profileId,
    );
    final groupId = created.group.id;
    final priya = await a.groups.addMember(groupId, displayName: 'Priya');
    final arun = await a.groups.addMember(groupId, displayName: 'Arun');
    final seed = (
      groupId: groupId,
      ravi: created.creator.id,
      priya: priya.id,
      arun: arun.id,
    );
    if (joined) await join(seed);
    return seed;
  }

  EntryDraft draft(
    Seed g,
    int amount, {
    String description = 'Dinner',
    List<String>? between,
    String? payer,
    DateTime? entryDate,
    String currency = 'INR',
  }) => EntryDraft(
    groupId: g.groupId,
    currency: currency,
    amountMinor: amount,
    description: description,
    entryDate: entryDate,
    split: EqualSplit(between ?? [g.ravi, g.priya]),
    payerAmounts: {payer ?? g.ravi: amount},
  );

  group('reference data', () {
    liveTest('arrives with a device\'s first sync', () async {
      await start();
      final currencies = await a.db.select(a.db.currencies).get();
      expect(currencies.map((c) => c.code), contains('INR'));
      expect(await a.db.select(a.db.categories).get(), isNotEmpty);
    });

    liveTest('a row the server no longer lists stays on the device', () async {
      // Upsert, never delete: entries still reference a withdrawn row.
      await start();
      await a.db
          .into(a.db.currencies)
          .insert(
            CurrenciesCompanion.insert(code: 'XTS', exponent: 2, name: 'Test'),
          );
      await a.sync.syncEverything();

      final held = await a.db.select(a.db.currencies).get();
      expect(held.map((c) => c.code), contains('XTS'));
    });

    liveTest('a renamed row is corrected in place', () async {
      await start();
      await (a.db.update(a.db.currencies)..where((t) => t.code.equals('INR')))
          .write(const CurrenciesCompanion(name: Value('Stale name')));
      await a.sync.syncEverything();

      final inr = await (a.db.select(
        a.db.currencies,
      )..where((t) => t.code.equals('INR'))).getSingle();
      expect(inr.name, 'Indian Rupee');
    });
  });

  group('two devices converge', () {
    liveTest(
      'a hung upload times out without dropping the pending write',
      () async {
        final g = await seedGroup();
        await a.entries.create(draft(g, 100), createdBy: g.ravi);
        final release = Completer<void>();
        a.tap.before = (request) async {
          if (isUpsert(request)) await release.future;
        };

        final report = await a
            .engine(requestTimeout: const Duration(milliseconds: 200))
            .syncEverything();

        expect(report.failed, 1);
        expect(await a.outbox.pendingCount(), 1);
        release.complete();
      },
    );

    liveTest(
      'sign-out fences responses already in flight and future background sync',
      () async {
        await seedGroup();
        await a.sync.syncEverything();
        final entered = Completer<void>();
        final release = Completer<void>();
        a.tap.before = (request) async {
          if (!isGroupList(request) || entered.isCompleted) return;
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
        expect((await a.engine().syncEverything()).isClean, isFalse);
        expect(await a.db.select(a.db.groups).get(), isEmpty);
      },
    );

    liveTest(
      'an edit during upload survives acknowledgement of the older edit',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(draft(g, 1000), createdBy: g.ravi);
        var edited = false;
        a.tap.before = (request) async {
          if (!isUpsert(request) || edited) return;
          edited = true;
          await a.entries.update(entry.id, draft(g, 2500), actorId: g.ravi);
        };

        final report = await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        expect(report.isClean, isTrue, reason: '$report');
        expect(a.tap.requests.where(isUpsert), hasLength(2));
        expect((await a.entries.getEntry(entry.id))!.amountMinor, 2500);
        expect((await b.entries.getEntry(entry.id))!.amountMinor, 2500);
        expect(await a.outbox.pendingCount(), 0);
      },
    );

    liveTest(
      'pending edits survive pulls even with a clock behind the server',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(draft(g, 1000), createdBy: g.ravi);
        await a.sync.syncGroup(g.groupId);

        final behind = DriftEntryRepository(
          a.db,
          outbox: a.outbox,
          clock: () => DateTime.utc(2000),
        );
        await behind.update(
          entry.id,
          draft(g, 3500, description: 'Edited offline'),
          actorId: g.ravi,
        );
        // Replay a page, as after a reconnect or a reset cursor.
        await a.db.delete(a.db.groupCursors).go();
        await a.sync.pull(g.groupId);

        expect((await a.entries.getEntry(entry.id))!.amountMinor, 3500);
        expect(await a.outbox.pendingCount(), 1);
      },
    );

    liveTest(
      'separate engine instances serialize through the database lease',
      () async {
        await seedGroup();
        await a.sync.syncEverything();

        final entered = Completer<void>();
        final release = Completer<void>();
        a.tap.requests.clear();
        a.tap.before = (request) async {
          if (!isGroupList(request) || entered.isCompleted) return;
          entered.complete();
          await release.future;
        };

        final first = a.sync.syncEverything();
        await entered.future;
        final second = a.engine().syncEverything();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          a.tap.requests.where(isGroupList),
          hasLength(1),
          reason: 'the second engine must not enter while the first holds it',
        );

        release.complete();
        await Future.wait([first, second]);
        expect(a.tap.requests.where(isGroupList), hasLength(2));
      },
    );

    liveTest('a new engine resumes after an abandoned lease expires', () async {
      await start();
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

    liveTest(
      'an expense added on A reaches B with identical balances',
      () async {
        final g = await seedGroup();
        await a.entries.create(
          draft(
            g,
            240000,
            description: 'Dinner at Toit',
            between: [g.ravi, g.priya, g.arun],
          ),
          createdBy: g.ravi,
        );

        final pushReport = await a.sync.syncGroup(g.groupId);
        expect(pushReport.isClean, isTrue, reason: '$pushReport');
        expect(
          pushReport.pushed,
          1,
          reason: 'the history line is the server\'s',
        );

        final pullReport = await b.sync.syncGroup(g.groupId);
        expect(pullReport.pulled, 1);
        expect(
          foldBalances(await b.ledger(g.groupId)),
          foldBalances(await a.ledger(g.groupId)),
        );
        expect(
          foldBalances(
            await b.ledger(g.groupId),
          ).map((x) => '${x.memberId}:${x.balanceMinor}'),
          contains('${g.ravi}:160000'),
        );
      },
    );

    liveTest(
      'edits made on both devices converge on the same journal',
      () async {
        final g = await seedGroup();
        final everyone = [g.ravi, g.priya, g.arun];
        await a.entries.create(
          draft(g, 240000, between: everyone),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        await b.entries.create(
          draft(
            g,
            90000,
            description: 'Auto',
            between: [g.priya, g.arun],
            payer: g.priya,
          ),
          createdBy: g.priya,
        );
        await a.entries.create(
          draft(
            g,
            60000,
            description: 'Coffee',
            between: [g.ravi, g.arun],
            payer: g.arun,
          ),
          createdBy: g.arun,
        );

        // Each device has to push before it can see the other's push.
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
      },
    );

    liveTest('a soft delete propagates rather than lingering on B', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(draft(g, 120000), createdBy: g.ravi);
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      expect(foldBalances(await b.ledger(g.groupId)), hasLength(2));

      await a.entries.delete(entry.id, actorId: g.ravi);
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      final onB = await b.ledger(g.groupId);
      expect(onB.single.isDeleted, isTrue);
      expect(foldBalances(onB), isEmpty);
    });

    liveTest(
      'a stale delete is parked instead of erasing a newer edit',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          draft(g, 100000, description: 'Original'),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        await a.entries.update(
          entry.id,
          draft(g, 200000, description: 'Corrected'),
          actorId: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);

        await b.entries.delete(entry.id, actorId: g.priya);
        await b.sync.syncGroup(g.groupId);

        final current = (await b.ledger(g.groupId)).single;
        expect(current.isDeleted, isFalse);
        expect(current.amountMinor, 200000);

        final conflicts = await DriftConflictRepository(b.db).watchAll().first;
        expect(conflicts.single.attempted.deletedAt, isNotNull);
        expect(conflicts.single.current?.amountMinor, 200000);
      },
    );

    liveTest('the last write wins, judged by the server', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(
        draft(g, 100000, description: 'Original'),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      await a.entries.update(
        entry.id,
        draft(g, 100000, description: 'Edited on A'),
        actorId: g.ravi,
      );
      await b.entries.update(
        entry.id,
        draft(g, 100000, description: 'Edited on B'),
        actorId: g.priya,
      );

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId); // B pushes second, so B wins.
      await a.sync.syncGroup(g.groupId);

      expect((await a.ledger(g.groupId)).single.description, 'Edited on B');
      expect((await b.ledger(g.groupId)).single.description, 'Edited on B');
    });
  });

  group('the server is the backstop', () {
    /// An expense whose shares no longer add up, as a client bug would leave it.
    Future<String> corrupted(Seed g, {String description = 'Dinner'}) async {
      final entry = await a.entries.create(
        draft(g, 100000, description: description),
        createdBy: g.ravi,
      );
      await (a.db.update(a.db.entryShares)
            ..where((t) => t.entryId.equals(entry.id)))
          .write(const EntrySharesCompanion(amountMinor: Value(1)));
      await a.outbox.enqueue(OutboxTarget.entry, entry.id);
      return entry.id;
    }

    liveTest('an unbalanced entry is rejected and never stored', () async {
      final g = await seedGroup();
      await corrupted(g);

      final report = await a.sync.syncGroup(g.groupId);
      expect(report.failed, greaterThan(0));

      await b.sync.syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), isEmpty);
    });

    liveTest('a permanently rejected item is set aside, described', () async {
      final g = await seedGroup();
      await corrupted(g, description: "Dinner at Britto's");

      await a.sync.syncGroup(g.groupId);

      expect(await a.outbox.pendingCount(), 0, reason: 'it cannot wedge');
      final failures = await a.outbox.watchDeadLetters().first;
      expect(failures.single.target, OutboxTarget.entry);
      expect(failures.single.label, "Dinner at Britto's");
      expect(failures.single.reason, contains('does not add up'));
    });

    liveTest(
      'a refused write can be retried once its cause is fixed',
      () async {
        final g = await seedGroup();
        final id = await corrupted(g);
        await a.sync.syncGroup(g.groupId);
        expect(await a.outbox.deadLetters(), hasLength(1));

        await (a.db.update(a.db.entryShares)
              ..where((t) => t.entryId.equals(id)))
            .write(const EntrySharesCompanion(amountMinor: Value(50000)));
        expect(await a.outbox.retryDeadLetters(), 1);
        await a.sync.syncGroup(g.groupId);

        expect(await a.outbox.deadLetters(), isEmpty);
        expect(await a.outbox.pendingCount(), 0, reason: 'it landed');
      },
    );

    group('discarding a refused write', () {
      Future<List<GroupEventRow>> provisionalLines(String entryId) =>
          (a.db.select(
            a.db.groupEvents,
          )..where((t) => t.subjectId.equals(entryId) & t.isProvisional)).get();

      void refuseUploads() => a.tap.before = (request) async {
        if (isUpsert(request)) throw refused(request);
      };

      liveTest('puts back the server\'s version of an edit', () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          draft(g, 60000),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);

        refuseUploads();
        await a.entries.update(entry.id, draft(g, 90000), actorId: g.ravi);
        await a.sync.syncGroup(g.groupId);
        expect(await a.outbox.deadLetters(), hasLength(1));

        a.tap.before = null;
        await a.sync.discardRefused();
        await a.sync.syncGroup(g.groupId);

        expect((await a.entries.getEntry(entry.id))!.amountMinor, 60000);
        expect(await a.outbox.deadLetters(), isEmpty);
        expect(await a.outbox.pendingCount(), 0);
        expect(await provisionalLines(entry.id), isEmpty);
      });

      liveTest('removes a row the server never had', () async {
        final g = await seedGroup();
        refuseUploads();
        final entry = await a.entries.create(
          draft(g, 60000),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        expect(await a.outbox.deadLetters(), hasLength(1));

        await a.sync.discardRefused();

        expect(await a.entries.getEntry(entry.id), isNull);
        expect(await provisionalLines(entry.id), isEmpty);
        expect(await a.outbox.deadLetters(), isEmpty);
      });
    });

    liveTest('a retried push does not create a second entry', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(draft(g, 100000), createdBy: g.ravi);
      await a.sync.syncGroup(g.groupId);

      // A response lost in transit: the client queues the same row again.
      await a.outbox.enqueue(OutboxTarget.entry, entry.id);
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      expect(a.tap.requests.where(isUpsert), hasLength(2));
      expect(await b.ledger(g.groupId), hasLength(1));
    });
  });

  group('the cursor', () {
    liveTest('pages through more entries than fit in one request', () async {
      final g = await seedGroup();
      for (var i = 0; i < 25; i++) {
        await a.entries.create(
          draft(g, 1000 + i, description: 'Expense $i'),
          createdBy: g.ravi,
        );
      }
      await a.sync.syncGroup(g.groupId);

      await b.engine(pageSize: 4).syncGroup(g.groupId);

      expect(await b.ledger(g.groupId), hasLength(25));
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
    });

    liveTest('gives every committed change a number of its own', () async {
      final g = await seedGroup();
      for (var i = 0; i < 12; i++) {
        await a.entries.create(
          draft(g, 5000, description: 'Batched $i'),
          createdBy: g.ravi,
        );
      }
      await a.sync.push();

      final stamps = [for (final e in await a.ledger(g.groupId)) e.seq!]
        ..sort();
      expect(
        stamps,
        orderedEquals([for (var i = 0; i < 12; i++) stamps.first + i]),
        reason:
            'none reused and none skipped, so a cursor cannot step over one',
      );

      await b.engine(pageSize: 5).syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), hasLength(12));
    });

    liveTest('a second sync with no changes pulls nothing', () async {
      final g = await seedGroup();
      await a.entries.create(draft(g, 100000), createdBy: g.ravi);
      await a.sync.syncGroup(g.groupId);

      expect((await b.sync.syncGroup(g.groupId)).pulled, 1);
      expect((await b.sync.syncGroup(g.groupId)).pulled, 0);
    });
  });

  group('offline replay', () {
    liveTest('a queue built with no server drains once it appears', () async {
      final g = await seedGroup(joined: false);
      for (var i = 0; i < 5; i++) {
        await a.entries.create(
          draft(
            g,
            10000 * (i + 1),
            description: 'Offline $i',
            between: [g.ravi, g.priya, g.arun],
          ),
          createdBy: g.ravi,
        );
      }
      expect(await a.outbox.pendingCount(), 9, reason: 'group, 3 members, 5');

      await join(g);
      expect(await a.outbox.pendingCount(), 0);
      expect(await b.ledger(g.groupId), hasLength(5));
      expect(
        foldBalances(await b.ledger(g.groupId)),
        foldBalances(await a.ledger(g.groupId)),
      );
    });

    liveTest('a queue longer than one page drains in a single sync', () async {
      final g = await seedGroup(joined: false);
      const count = 120;
      for (var i = 0; i < count; i++) {
        await a.entries.create(
          draft(g, 10000 + i, description: 'Offline $i'),
          createdBy: g.ravi,
        );
      }
      expect(await a.outbox.pendingCount(), count + 4);

      final report = await a.sync.syncGroup(g.groupId);
      expect(report.failed, 0);
      expect(await a.outbox.pendingCount(), 0);

      await b.claim(a, g.groupId, g.priya);
      await b.sync.syncGroup(g.groupId);
      expect(await b.ledger(g.groupId), hasLength(count));
    });

    liveTest(
      'an offline edit does not reorder a row ahead of its group',
      () async {
        final g = await seedGroup(joined: false);
        await a.entries.create(draft(g, 40000), createdBy: g.ravi);
        final group = (await a.groups.getGroup(g.groupId))!;
        await a.groups.updateGroup(group.copyWith(name: 'Goa trip'));
        await a.groups.renameMember(g.priya, 'Priya S');

        expect(
          [for (final row in await a.outbox.due()) row.target],
          [
            OutboxTarget.group,
            OutboxTarget.member,
            OutboxTarget.member,
            OutboxTarget.member,
            OutboxTarget.entry,
          ],
          reason: 'the group has to reach the server before anything naming it',
        );

        await join(g);
        expect(await a.outbox.deadLetters(), isEmpty);
        expect(await a.outbox.pendingCount(), 0);
        expect((await b.groups.getGroup(g.groupId))!.name, 'Goa trip');
        expect(await b.ledger(g.groupId), hasLength(1));
      },
    );
  });

  group('group and member rows', () {
    liveTest(
      'a local rename survives a pull that runs before it is pushed',
      () async {
        final g = await seedGroup();
        final group = (await a.groups.getGroup(g.groupId))!;
        await a.groups.updateGroup(group.copyWith(name: 'Goa Trip 2026'));

        await a.sync.pull(g.groupId);

        expect((await a.groups.getGroup(g.groupId))!.name, 'Goa Trip 2026');
      },
    );

    liveTest('a remote rename wins once it is genuinely newer', () async {
      final g = await seedGroup();
      final onB = (await b.groups.getGroup(g.groupId))!;
      await b.groups.updateGroup(onB.copyWith(name: 'Renamed on B'));
      await b.sync.syncGroup(g.groupId);

      await a.sync.syncGroup(g.groupId);
      expect((await a.groups.getGroup(g.groupId))!.name, 'Renamed on B');
    });

    liveTest('a member rename converges across devices', () async {
      final g = await seedGroup();
      await b.groups.renameMember(g.priya, 'Priya S');
      await b.sync.syncGroup(g.groupId);
      await a.sync.syncGroup(g.groupId);

      final members = await a.groups.getMembers(g.groupId);
      expect(members.firstWhere((m) => m.id == g.priya).displayName, 'Priya S');
    });

    liveTest(
      'a stale rename cannot un-claim somebody who just joined',
      () async {
        final g = await seedGroup(joined: false);
        await a.sync.syncGroup(g.groupId);
        await b.claim(a, g.groupId, g.priya);

        // A still believes Priya is a placeholder and renames her.
        await a.groups.renameMember(g.priya, 'Priya S');
        await a.sync.syncGroup(g.groupId);

        expect(
          (await a.outbox.watchDeadLetters().first).single.reason,
          contains('Only Priya'),
          reason: 'she has an account now, so her name is hers',
        );
        expect(await b.sync.discoverGroups(), contains(g.groupId));
      },
    );
  });

  group('exchange rates', () {
    /// What the rate feed has published, served in place of the Worker's.
    late List<api.FxRate> published;

    void serveRates(Device device) {
      published = [];
      device.tap.answer = (request) {
        if (request.method != 'GET' || !request.path.endsWith('/api/fx')) {
          return null;
        }
        final since = request.queryParameters['since'] as String;
        return api.FxPage(
          rates: [
            for (final rate in published)
              if (rate.asOf.compareTo(since) >= 0) rate,
          ],
          hasMore: false,
        ).toJson();
      };
    }

    void publish(String asOf, String currency, num rate) => published.add(
      api.FxRate(asOf: asOf, currency: currency, rate: rate, source_: 'test'),
    );

    String? lastSince() =>
        a.tap.last('GET', '/api/fx')?.queryParameters['since'] as String?;

    liveTest('arrive with sync and are then left alone', () async {
      final g = await seedGroup(joined: false);
      serveRates(a);
      publish('2026-08-20', 'USD', 1);
      publish('2026-08-20', 'INR', 95.43);

      await a.sync.syncGroup(g.groupId);
      expect(await a.db.select(a.db.fxRates).get(), hasLength(2));

      await a.sync.syncGroup(g.groupId);
      expect(lastSince(), '2026-08-20', reason: 'from the newest date held');
      expect(await a.db.select(a.db.fxRates).get(), hasLength(2));
    });

    liveTest('a later publication does not disturb the earlier one', () async {
      final g = await seedGroup(joined: false);
      serveRates(a);
      publish('2026-08-20', 'INR', 95.43);
      await a.sync.syncGroup(g.groupId);

      publish('2026-08-21', 'INR', 95.70);
      await a.sync.syncGroup(g.groupId);

      final stored = await a.db.select(a.db.fxRates).get()
        ..sort((x, y) => x.asOf.compareTo(y.asOf));
      expect(stored.map((r) => r.asOf), ['2026-08-20', '2026-08-21']);
      expect(stored.first.rate, closeTo(95.43, 1e-9));
    });

    liveTest('reaches back for a day a backdated expense needs', () async {
      final g = await seedGroup(joined: false);
      serveRates(a);
      publish('2026-08-20', 'USD', 1);
      await a.sync.syncGroup(g.groupId);
      expect(lastSince(), isNot('2024-03-11'));

      // In a currency that is not the group's own, so it needs a rate.
      await a.entries.create(
        draft(
          g,
          4200,
          currency: 'USD',
          entryDate: DateTime.utc(2024, 3, 11),
          between: [g.ravi],
        ),
        createdBy: g.ravi,
      );
      publish('2024-03-11', 'USD', 1);
      await a.sync.syncGroup(g.groupId);

      expect(lastSince(), '2024-03-11');
      expect(
        (await a.db.select(a.db.fxRates).get()).map((row) => row.asOf),
        contains('2024-03-11'),
      );
    });

    liveTest('widens the window once, not on every sync forever', () async {
      final g = await seedGroup(joined: false);
      serveRates(a);
      await a.entries.create(
        draft(
          g,
          4200,
          currency: 'USD',
          entryDate: DateTime.utc(1999, 1, 1),
          between: [g.ravi],
        ),
        createdBy: g.ravi,
      );

      await a.sync.syncGroup(g.groupId);
      expect(lastSince(), '1999-01-01');

      await a.sync.syncGroup(g.groupId);
      expect(lastSince(), isNot('1999-01-01'));
    });

    liveTest('a rate failure never fails a sync that carries money', () async {
      final g = await seedGroup(joined: false);
      a.tap.before = (request) async {
        if (request.path.endsWith('/api/fx')) throw offline(request);
      };
      final report = await a.sync.syncGroup(g.groupId);
      expect(report.isClean, isTrue, reason: '$report');
    });
  });

  group('finding groups this device has never seen', () {
    liveTest(
      'a failed cursor write rolls back its page and can be retried',
      () async {
        final g = await seedGroup();
        await a.entries.create(draft(g, 90000), createdBy: g.ravi);
        expect((await a.sync.syncEverything()).isClean, isTrue);

        final other = await Device.sameAccountAs(a);
        await other.db.customStatement('''
        CREATE TRIGGER reject_group_cursor BEFORE INSERT ON group_cursors
        BEGIN SELECT RAISE(ABORT, 'test cursor failure'); END;
      ''');

        expect((await other.sync.syncEverything()).isClean, isFalse);
        expect(await other.db.select(other.db.members).get(), isEmpty);
        expect(await other.db.select(other.db.entries).get(), isEmpty);
        expect(await other.db.select(other.db.groupEvents).get(), isEmpty);
        expect(await other.db.select(other.db.groupCursors).get(), isEmpty);

        await other.db.customStatement('DROP TRIGGER reject_group_cursor');
        expect((await other.sync.syncEverything()).isClean, isTrue);
        expect(await other.db.select(other.db.members).get(), hasLength(3));
        expect(await other.ledger(g.groupId), hasLength(1));
      },
    );

    liveTest('a fresh device discovers the groups it belongs to', () async {
      final g = await seedGroup(joined: false);
      await a.entries.create(
        draft(g, 240000, between: [g.ravi]),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);

      final other = await Device.sameAccountAs(a);
      final found = await other.sync.discoverGroups();
      expect(found, [g.groupId]);

      await other.sync.syncGroup(g.groupId);
      expect(
        (await other.db.select(other.db.groups).get()).single.name,
        'Goa Trip',
      );
      expect((await other.ledger(g.groupId)).single.amountMinor, 240000);
    });

    liveTest('a group left behind is not rediscovered', () async {
      final g = await seedGroup(joined: false);
      await a.sync.syncGroup(g.groupId);
      await a.groups.leaveGroup(groupId: g.groupId, memberId: g.ravi);
      await a.sync.syncGroup(g.groupId);

      expect(
        await (await Device.sameAccountAs(a)).sync.discoverGroups(),
        isEmpty,
      );
    });

    liveTest(
      'failed discovery is not a successful local-only answer',
      () async {
        final g = await seedGroup(joined: false);
        a.tap.before = (request) async {
          if (isGroupList(request)) throw offline(request);
        };

        await expectLater(a.sync.discoverGroups(), throwsA(isA<ApiFailure>()));
        expect((await a.db.select(a.db.groups).get()).single.id, g.groupId);
        expect(await a.outbox.pendingCount(), greaterThan(0));
      },
    );

    liveTest(
      'an empty device reports a discovery failure and can recover',
      () async {
        await start();
        b.tap.before = (request) async {
          if (isGroupList(request)) throw offline(request);
        };

        final failed = await b.sync.syncEverything();
        expect(failed.error, isA<ApiFailure>());
        expect(await b.db.select(b.db.groups).get(), isEmpty);

        b.tap.before = null;
        expect((await b.sync.syncEverything()).isClean, isTrue);
      },
    );
  });

  group('a name follows the account, not the group', () {
    Future<void> rename(Device device, String name) => fetch(
      device.client.getSyncApi().updateProfile(
        profileUpdate: api.ProfileUpdate(displayName: name, upiVpa: null),
      ),
    );

    liveTest(
      'an invite claim hydrates a profile older than the feed cursor',
      () async {
        final g = await seedGroup(joined: false);
        await a.sync.syncGroup(g.groupId);

        // B was named before A could see it; A's own later rename moves A's
        // feed cursor past B's row.
        await rename(b, 'Priya D');
        await rename(a, 'Ravi');
        await a.sync.shared.pullProfiles();

        await b.claim(a, g.groupId, g.priya);
        await a.sync.syncGroup(g.groupId);

        final profile = await DriftProfileRepository(a.db).byId(b.profileId);
        expect(profile?.displayName, 'Priya D');
      },
    );

    liveTest('a rename by somebody else arrives on the next sync', () async {
      await seedGroup();
      await rename(b, 'Priya');
      await a.sync.shared.pullProfiles();
      expect(
        (await DriftProfileRepository(a.db).byId(b.profileId))?.displayName,
        'Priya',
      );

      await rename(b, 'Priya S');
      await a.sync.shared.pullProfiles();
      expect(
        (await DriftProfileRepository(a.db).byId(b.profileId))?.displayName,
        'Priya S',
      );
    });

    liveTest('the cursor stops it re-fetching what it already has', () async {
      await start();
      String? after() =>
          a.tap.last('GET', '/api/profiles')?.queryParameters['after']
              as String?;

      await a.sync.shared.pullProfiles();
      expect(after(), isNull, reason: 'the first pull asks for everything');

      await a.sync.shared.pullProfiles();
      expect(after(), isNotNull, reason: 'the second asks only for changes');
    });
  });

  group('the activity feed', () {
    liveTest('reaches the other device, once and only once', () async {
      final g = await seedGroup();
      final entry = await a.entries.create(draft(g, 120000), createdBy: g.ravi);
      await a.entries.update(entry.id, draft(g, 100000), actorId: g.ravi);

      expect((await a.feed(g.groupId)).map((e) => e.kind), [
        EntryEventKind.edited,
        EntryEventKind.created,
      ], reason: 'provisional, but on screen the moment each save happened');

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      // The outbox coalesces by row, so the server committed one expense and
      // recorded that; A's provisional pair is superseded.
      expect((await b.feed(g.groupId)).map((e) => e.kind), [
        EntryEventKind.created,
      ]);
      expect((await a.feed(g.groupId)).single.isProvisional, isFalse);

      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);
      expect(await a.feed(g.groupId), hasLength(1));
      expect(await b.feed(g.groupId), hasLength(1));
    });

    liveTest(
      'an edit the server witnesses separately is its own line',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          draft(g, 120000),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        await a.entries.update(entry.id, draft(g, 100000), actorId: g.ravi);
        await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        final feed = await b.feed(g.groupId);
        expect(feed.map((e) => e.kind), [
          EntryEventKind.edited,
          EntryEventKind.created,
        ]);
        final amount = feed.first.changes.singleWhere(
          (c) => c.field == 'amount_minor',
        );
        expect(amount.from, '120000');
        expect(amount.to, '100000');
        expect(feed.first.actorId, g.ravi, reason: 'resolved from the session');
      },
    );

    liveTest(
      'a re-split is recorded even though the total never moves',
      () async {
        final g = await seedGroup();
        final entry = await a.entries.create(
          draft(g, 40000),
          createdBy: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);

        await a.entries.update(
          entry.id,
          EntryDraft(
            groupId: g.groupId,
            currency: 'INR',
            amountMinor: 40000,
            description: 'Dinner',
            split: ExactSplit({g.ravi: 10000, g.priya: 30000}),
            payerAmounts: {g.ravi: 40000},
          ),
          actorId: g.ravi,
        );
        await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);

        final latest = (await b.feed(g.groupId)).first;
        expect(latest.kind, EntryEventKind.edited);
        expect(
          latest.changes.map((c) => c.field),
          containsAll(['share:${g.ravi}', 'share:${g.priya}']),
        );
        expect(
          latest.changes.singleWhere((c) => c.field == 'share:${g.priya}').to,
          '30000',
        );
      },
    );

    liveTest(
      'is not skipped when a device stamps its own clock ahead',
      () async {
        final g = await seedGroup();
        await a.entries.create(draft(g, 120000), createdBy: g.ravi);

        // A's provisional line carries a clock a year fast; it is never pushed
        // and must move no cursor.
        await (a.db.update(a.db.groupEvents)).write(
          GroupEventsCompanion(createdAt: Value(DateTime.utc(2027, 8, 21))),
        );

        await a.sync.syncGroup(g.groupId);
        await b.sync.syncGroup(g.groupId);
        expect(await b.feed(g.groupId), hasLength(1));

        await b.entries.create(
          draft(g, 60000, description: 'Taxi', payer: g.priya),
          createdBy: g.priya,
        );
        await b.sync.syncGroup(g.groupId);
        await a.sync.syncGroup(g.groupId);

        expect(await a.feed(g.groupId), hasLength(2));
      },
    );
  });

  group('an edit overtaken by somebody else', () {
    /// Both hold the expense; B's edit lands first, so A's is composed against
    /// a version that no longer exists.
    Future<({Seed g, String entryId})> divergent({
      required int raviAmount,
      required String raviDescription,
      required int priyaAmount,
    }) async {
      final g = await seedGroup();
      final everyone = [g.ravi, g.priya, g.arun];
      final entry = await a.entries.create(
        draft(g, 30000, between: everyone),
        createdBy: g.ravi,
      );
      await a.sync.syncGroup(g.groupId);
      await b.sync.syncGroup(g.groupId);

      await b.entries.update(
        entry.id,
        draft(g, priyaAmount, between: everyone),
        actorId: g.priya,
      );
      await b.sync.syncGroup(g.groupId);

      await a.entries.update(
        entry.id,
        draft(g, raviAmount, description: raviDescription, between: everyone),
        actorId: g.ravi,
      );
      return (g: g, entryId: entry.id);
    }

    liveTest(
      'converges even when a pull skipped the newer version first',
      () async {
        final (:g, entryId: _) = await divergent(
          raviAmount: 60000,
          raviDescription: 'Dinner',
          priyaAmount: 45000,
        );

        // The push fails once, but the pull in the same run skips the newer row
        // (A's edit is still queued) and moves the cursor past it.
        var failOnce = true;
        a.tap.before = (request) async {
          if (isUpsert(request) && failOnce) {
            failOnce = false;
            throw offline(request);
          }
        };
        await a.sync.syncGroup(g.groupId);
        await a.db
            .update(a.db.outbox)
            .write(const OutboxCompanion(nextAttemptAt: Value(null)));

        await a.sync.syncGroup(g.groupId);

        expect((await a.ledger(g.groupId)).single.amountMinor, 45000);
        final conflict = (await DriftConflictRepository(
          a.db,
        ).watchAll().first).single;
        expect(conflict.attempted.amountMinor, 60000);
        expect(conflict.current?.amountMinor, 45000);
      },
    );

    liveTest('the ledger converges and the edit is kept', () async {
      final (:g, entryId: _) = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      expect((await a.ledger(g.groupId)).single.amountMinor, 45000);
      final conflicts = await DriftConflictRepository(a.db).watchAll().first;
      expect(conflicts.single.attempted.amountMinor, 60000);
      expect(conflicts.single.current?.amountMinor, 45000);
      expect(await a.outbox.pendingCount(), 0, reason: 'not refused forever');
      expect(
        await a.outbox.deadLetters(),
        isEmpty,
        reason: 'nor a dead letter',
      );
    });

    liveTest('an edit that moves no money is simply applied', () async {
      final (:g, entryId: _) = await divergent(
        raviAmount: 45000,
        raviDescription: 'Dinner at Toit',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      expect(await DriftConflictRepository(a.db).watchAll().first, isEmpty);
      expect((await a.ledger(g.groupId)).single.description, 'Dinner at Toit');
      await b.sync.syncGroup(g.groupId);
      expect((await b.ledger(g.groupId)).single.description, 'Dinner at Toit');
    });

    liveTest('editing it again lands, and clears the notice', () async {
      final (:g, :entryId) = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      final conflicts = DriftConflictRepository(a.db);
      expect(await conflicts.byEntry(entryId), isNotNull);

      await a.entries.update(
        entryId,
        draft(g, 60000, between: [g.ravi, g.priya, g.arun]),
        actorId: g.ravi,
      );
      expect(await conflicts.byEntry(entryId), isNull);

      await a.sync.syncGroup(g.groupId);
      expect((await a.ledger(g.groupId)).single.amountMinor, 60000);
      await b.sync.syncGroup(g.groupId);
      expect((await b.ledger(g.groupId)).single.amountMinor, 60000);
    });

    liveTest('the feed records the edit A never saw', () async {
      final (:g, entryId: _) = await divergent(
        raviAmount: 60000,
        raviDescription: 'Dinner',
        priyaAmount: 45000,
      );
      await a.sync.syncGroup(g.groupId);

      expect(
        (await a.feed(g.groupId)).any((l) => l.kind == EntryEventKind.edited),
        isTrue,
      );
    });
  });

  group('one engine, one feed', () {
    /// A third member's device, holding nothing.
    Future<Device> arunsDevice(Seed g) async {
      final device = await Device.guest();
      await device.claim(a, g.groupId, g.arun);
      return device;
    }

    Future<void> addExpenses(Seed g, int count) async {
      for (var i = 0; i < count; i++) {
        await a.entries.create(
          draft(
            g,
            30000,
            description: 'Dinner $i',
            between: [g.ravi, g.priya, g.arun],
          ),
          createdBy: g.ravi,
        );
      }
    }

    liveTest('a feed that spans several pages arrives whole', () async {
      final g = await seedGroup();
      await addExpenses(g, 5);
      await a.sync.syncGroup(g.groupId);

      final device = await arunsDevice(g);
      await device.engine(pageSize: 2).pull(g.groupId);

      expect(await device.entries.getEntries(g.groupId), hasLength(5));
      expect(await device.feed(g.groupId), hasLength(5));
    });

    liveTest('a page is never cut inside one change', () async {
      final g = await seedGroup();
      await a.sync.syncGroup(g.groupId);
      final beforeExpenses =
          (await a.db.select(a.db.groupCursors).getSingle()).seq;

      await addExpenses(g, 3);
      await a.sync.syncGroup(g.groupId);

      // An expense and its history line share a number, and so a page.
      final firstPage = await fetch(
        a.client.getSyncApi().getChanges(
          groupId: g.groupId,
          since: beforeExpenses,
          limit: 1,
        ),
      );
      expect(firstPage.entries, hasLength(1));
      expect(firstPage.events.map((event) => event.seq), [
        firstPage.entries.single.seq,
      ]);
      expect(firstPage.hasMore, isTrue);

      final device = await arunsDevice(g);
      await device.engine(pageSize: 1).pull(g.groupId);
      expect(await device.entries.getEntries(g.groupId), hasLength(3));
      expect(await device.feed(g.groupId), hasLength(3));
    });

    liveTest('a settled feed costs an empty answer, not a refetch', () async {
      final g = await seedGroup();
      await addExpenses(g, 1);
      await a.sync.syncGroup(g.groupId);

      final device = await arunsDevice(g);
      await device.sync.syncGroup(g.groupId);
      expect((await device.sync.syncGroup(g.groupId)).pulled, 0);
    });
  });
}
