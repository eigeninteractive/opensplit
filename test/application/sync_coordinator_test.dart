import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/sync_coordinator.dart';
import 'package:opensplit/data/sync/sync_engine.dart';

const _clean = SyncReport(pushed: 0, pulled: 0, failed: 0);
final _failed = SyncReport(
  pushed: 0,
  pulled: 0,
  failed: 0,
  error: StateError('discovery unavailable'),
);

void main() {
  testWidgets('a first group refresh bootstraps the account', (tester) async {
    final first = Completer<SyncReport>();
    var fullRuns = 0;
    final groups = <String>[];
    final coordinator = SyncCoordinator(
      syncAll: () {
        fullRuns++;
        return first.future;
      },
      syncGroup: (id) async {
        groups.add(id);
        return _clean;
      },
    );
    addTearDown(coordinator.dispose);

    final run = coordinator.syncGroup('home');
    await tester.pump();
    expect(coordinator.status.isSyncing, isTrue);
    expect(coordinator.status.hasCompletedFullSync, isFalse);
    first.complete(_clean);
    await run;
    expect(coordinator.status.hasCompletedFullSync, isTrue);
    expect(coordinator.status.isSyncing, isFalse);

    await coordinator.syncGroup('home');
    expect(fullRuns, 1);
    expect(groups, ['home']);
  });

  testWidgets('requests during a run coalesce into one follow-up', (
    tester,
  ) async {
    final first = Completer<SyncReport>();
    var fullRuns = 0;
    final coordinator = SyncCoordinator(
      syncAll: () async => ++fullRuns == 1 ? await first.future : _clean,
      syncGroup: (_) async => throw StateError('full sync should cover this'),
    );
    addTearDown(coordinator.dispose);

    final run = coordinator.syncAll();
    await tester.pump();
    final afterWrite = coordinator.syncAll();
    final afterWake = coordinator.syncGroup('home');
    expect(fullRuns, 1);
    first.complete(_clean);
    await Future.wait([run, afterWrite, afterWake]);

    expect(fullRuns, 2);
    expect(coordinator.status.error, isNull);
  });

  testWidgets('a failure stays visible and retries without another trigger', (
    tester,
  ) async {
    var attempts = 0;
    final coordinator = SyncCoordinator(
      syncAll: () async => ++attempts == 1 ? _failed : _clean,
      syncGroup: (_) async => _clean,
    );
    addTearDown(coordinator.dispose);

    await coordinator.syncAll();
    expect(coordinator.status.error, same(_failed.error));
    expect(coordinator.status.hasCompletedFullSync, isFalse);
    expect(coordinator.status.retryAt, isNotNull);

    await tester.pump(const Duration(seconds: 4));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 2);
    expect(coordinator.status.hasCompletedFullSync, isTrue);
    expect(coordinator.status.error, isNull);
    expect(coordinator.status.retryAt, isNull);
  });

  testWidgets('retry backoff grows, caps at five minutes, and resets', (
    tester,
  ) async {
    var attempts = 0;
    var fail = true;
    final coordinator = SyncCoordinator(
      syncAll: () async {
        attempts++;
        return fail ? _failed : _clean;
      },
      syncGroup: (_) async => _clean,
    );
    await coordinator.syncAll();
    for (final seconds in [5, 10, 20, 40, 80, 160, 300, 300]) {
      final before = attempts;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(attempts, before);
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, before + 1);
    }
    fail = false;
    await coordinator.syncAll();
    expect(coordinator.status.retryAt, isNull);
    fail = true;
    await coordinator.syncAll();
    final before = attempts;
    await tester.pump(const Duration(seconds: 5));
    expect(attempts, before + 1);
    coordinator.dispose();
  });

  testWidgets('restores an outbox deadline even when nothing was due', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 28);
    final waiting = SyncReport(
      pushed: 0,
      pulled: 0,
      failed: 0,
      nextPushAt: now.add(const Duration(seconds: 30)),
    );
    var attempts = 0;
    final coordinator = SyncCoordinator(
      syncAll: () async => ++attempts == 1 ? waiting : _clean,
      syncGroup: (_) async => _clean,
      clock: () => now,
    );
    addTearDown(coordinator.dispose);

    await coordinator.syncAll();
    expect(waiting.isClean, isFalse);
    expect(coordinator.status.hasCompletedFullSync, isTrue);
    expect(coordinator.status.retryAt, waiting.nextPushAt);
    await tester.pump(const Duration(seconds: 29));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 2);
    expect(coordinator.status.retryAt, isNull);
  });

  testWidgets('permanent refusals do not schedule automatic retries', (
    tester,
  ) async {
    final coordinator = SyncCoordinator(
      syncAll: () async => const SyncReport(pushed: 0, pulled: 1, failed: 1),
      syncGroup: (_) async => _clean,
    );
    addTearDown(coordinator.dispose);
    await coordinator.syncAll();
    expect(coordinator.status.lastReport!.failed, 1);
    expect(coordinator.status.hasCompletedFullSync, isTrue);
    expect(coordinator.status.error, isNull);
    expect(coordinator.status.retryAt, isNull);
  });

  testWidgets('a group request recovers the account after any failed refresh', (
    tester,
  ) async {
    var fail = false;
    var groupRuns = 0;
    final coordinator = SyncCoordinator(
      syncAll: () async => fail ? _failed : _clean,
      syncGroup: (_) async {
        groupRuns++;
        return _failed;
      },
    );
    await coordinator.syncAll();
    await coordinator.syncGroup('first');
    expect(groupRuns, 1);
    // Another group's success cannot mask a failure elsewhere: recover all.
    await coordinator.syncGroup('second');
    expect(groupRuns, 1);
    expect(coordinator.status.error, isNull);
    fail = true;
    await coordinator.syncAll();
    await coordinator.syncGroup('home');
    expect(groupRuns, 1);
    expect(coordinator.status.error, same(_failed.error));
    expect(coordinator.status.retryAt, isNotNull);
    coordinator.dispose();
  });

  testWidgets('disposing cancels retries and ignores late results', (
    tester,
  ) async {
    var attempts = 0;
    final pending = Completer<SyncReport>();
    final coordinator = SyncCoordinator(
      syncAll: () async {
        attempts++;
        return attempts == 1 ? _failed : await pending.future;
      },
      syncGroup: (_) async => _clean,
    );
    var updates = 0;
    coordinator.addListener(() => updates++);
    await coordinator.syncAll();
    final run = coordinator.syncAll();
    await tester.pump();
    coordinator.dispose();
    final before = updates;
    pending.complete(_clean);
    await run;
    await tester.pump(const Duration(minutes: 10));
    expect(attempts, 2);
    expect(updates, before);
    await coordinator.syncAll();
    expect(attempts, 2);
  });

  testWidgets('unexpected exceptions become visible failure reports', (
    tester,
  ) async {
    final coordinator = SyncCoordinator(
      syncAll: () => throw StateError('database unavailable'),
      syncGroup: (_) async => _clean,
    );
    await coordinator.syncAll();
    expect(coordinator.status.error, isA<StateError>());
    expect(coordinator.status.isSyncing, isFalse);
    expect(coordinator.status.retryAt, isNotNull);
    coordinator.dispose();
  });
}
