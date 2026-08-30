import 'dart:async';

import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/sync_gate_native.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('separate native gates serialize through the database', () async {
    final first = SqliteSyncGate(database);
    final second = SqliteSyncGate(database);
    final entered = Completer<void>();
    final release = Completer<void>();
    var secondEntered = false;

    final firstRun = first.synchronized(() async {
      entered.complete();
      await release.future;
      return 1;
    });
    await entered.future;
    final secondRun = second.synchronized(() async {
      secondEntered = true;
      return 2;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondEntered, isFalse);

    release.complete();
    expect(await firstRun, 1);
    expect(await secondRun, 2);
  });

  test('a lost renewal fails one run without poisoning later runs', () async {
    final gate = SqliteSyncGate(
      database,
      leaseLifetime: const Duration(seconds: 1),
      renewalInterval: const Duration(milliseconds: 10),
    );

    final first = gate.synchronized(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await database.delete(database.syncLeases).go();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      return 'stale';
    });
    await expectLater(first, throwsA(isA<StateError>()));

    expect(await gate.synchronized(() async => 'recovered'), 'recovered');
  });

  test('database failures are not disguised as lock contention', () async {
    final gate = SqliteSyncGate(
      database,
      waitTimeout: Duration.zero,
      pollInterval: Duration.zero,
    );
    await database.customStatement('DROP TABLE sync_leases');

    await expectLater(
      gate.synchronized(() async {}),
      throwsA(isNot(isA<TimeoutException>())),
    );
  });
}
