import 'dart:async';

import 'package:opensplit/application/sync_scheduler.dart';
import 'package:test/test.dart';

/// What makes a sync happen, and what deliberately does not.
///
/// Every one of these is a case where nothing visibly breaks when it is wrong,
/// which is why they are worth pinning: a missing trigger looks exactly like a
/// group where nobody has added anything, and a duplicated one looks exactly
/// like a working app that quietly costs battery and requests.
void main() {
  late List<DateTime> runs;
  late StreamController<bool> online;
  late DateTime now;
  late SyncScheduler scheduler;

  /// Lets a queued microtask -- the sync callback -- actually run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    runs = [];
    online = StreamController<bool>.broadcast();
    now = DateTime.utc(2026, 8, 27, 9);
    scheduler = SyncScheduler(
      sync: () async => runs.add(now),
      online: online.stream,
      clock: () => now,
      minimumGap: const Duration(minutes: 2),
    );
  });

  tearDown(() async {
    await scheduler.dispose();
    await online.close();
  });

  test('syncs once at launch', () async {
    scheduler.start();
    await settle();

    // The trigger that did not exist. Opening a group screen was the only
    // automatic sync, so a cold start showed whatever the device last knew --
    // and on a second device or after a reinstall, nothing at all.
    expect(runs, hasLength(1));
  });

  test('syncs when a network appears', () async {
    scheduler.start();
    await settle();
    now = now.add(const Duration(minutes: 5));

    online.add(true);
    await settle();

    expect(
      runs,
      hasLength(2),
      reason: 'surfacing from a tunnel with a queued expense used to push '
          'nothing until the user happened to pull down',
    );
  });

  test('does nothing when the network goes away', () async {
    scheduler.start();
    await settle();
    now = now.add(const Duration(minutes: 5));

    online.add(false);
    await settle();

    expect(runs, hasLength(1), reason: 'a sync cannot help with being offline');
  });

  test('collapses a flapping connection into one sync', () async {
    scheduler.start();
    await settle();

    // A phone on a train, switching between wifi and mobile data. Each of
    // these is a genuine connectivity event and none of them is news.
    for (var i = 0; i < 20; i++) {
      now = now.add(const Duration(seconds: 3));
      online.add(true);
      await settle();
    }

    expect(runs, hasLength(1));
  });

  test('syncs again once the gap has passed', () async {
    scheduler.start();
    await settle();

    now = now.add(const Duration(minutes: 1));
    online.add(true);
    await settle();
    expect(runs, hasLength(1), reason: 'too soon');

    now = now.add(const Duration(minutes: 2));
    online.add(true);
    await settle();
    expect(runs, hasLength(2), reason: 'and now it is not');
  });

  test('a resume syncs, but a glance at a notification does not', () async {
    scheduler.start();
    await settle();

    // Backgrounding an app for four seconds to read a notification is a
    // resume, and there is nothing new to fetch.
    now = now.add(const Duration(seconds: 4));
    scheduler.resumed();
    await settle();
    expect(runs, hasLength(1));

    now = now.add(const Duration(hours: 3));
    scheduler.resumed();
    await settle();
    expect(runs, hasLength(2), reason: 'a phone left closed overnight has news');
  });

  test('never runs two at once', () async {
    final started = <int>[];
    final gate = Completer<void>();
    final slow = SyncScheduler(
      sync: () async {
        started.add(started.length);
        await gate.future;
      },
      online: online.stream,
      clock: () => now,
      minimumGap: Duration.zero,
    );
    addTearDown(slow.dispose);

    slow.start();
    await settle();

    // Two pushes draining one outbox, and two pulls racing on one cursor.
    slow.resumed();
    online.add(true);
    await settle();

    expect(started, hasLength(1));
    gate.complete();
    await settle();
  });

  test('a failing sync does not stop the next one', () async {
    var attempts = 0;
    final failing = SyncScheduler(
      sync: () async {
        attempts++;
        throw StateError('offline');
      },
      online: online.stream,
      clock: () => now,
      minimumGap: Duration.zero,
    );
    addTearDown(failing.dispose);

    failing.start();
    await settle();
    online.add(true);
    await settle();

    // Walking into a lift must not wedge the scheduler for the session, and
    // must not surface an error either: nothing on screen depends on a sync.
    expect(attempts, 2);
  });

  test('stops listening once disposed', () async {
    scheduler.start();
    await settle();
    await scheduler.dispose();

    now = now.add(const Duration(hours: 1));
    online.add(true);
    await settle();

    expect(runs, hasLength(1));
  });
}
