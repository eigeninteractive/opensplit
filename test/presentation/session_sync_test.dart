import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/network/network_signal.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/fake_remote_ledger.dart';

import '../harness.dart';

final _account = Account(
  id: 'account',
  isAnonymous: false,
  email: null,
  displayName: null,
);
final _otherAccount = Account(
  id: 'other-account',
  isAnonymous: false,
  email: null,
  displayName: null,
);

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test('email verification updates the ledger identity before syncing', () async {
    final auth = _ChangingAuth();
    final syncedAccounts = <String?>[];
    final databases = <AppDatabase>[];
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        // In memory, like every other test here. Left real, this opens the
        // per-account file the app would -- which needs path_provider, and a
        // plugin channel that answers nothing outside a device.
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentAccountIdProvider);
          final db = AppDatabase(NativeDatabase.memory());
          databases.add(db);
          return db;
        }),
        remoteLedgerApiProvider.overrideWithValue(null),
        syncControllerProvider.overrideWith(
          () => _RecordingSync(syncedAccounts),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.events.close();
      for (final db in databases) {
        await db.close();
      }
    });
    container.listen(accountProvider, (_, _) {});
    await container.read(accountProvider.future);
    expect(container.read(currentAccountIdProvider), isNull);

    await container
        .read(accountControllerProvider.notifier)
        .verifyEmailCode(
          email: 'person@example.com',
          code: '01234567',
          flow: EmailFlow.signInPending,
        );

    // The SDK's current user is available before every stream consumer has
    // processed its notification. A sync must not use the cached signed-out id.
    expect(container.read(sessionControllerProvider)?.id, _account.id);
    expect(syncedAccounts, [_account.id]);
    auth.events.add(auth.currentUser);
    await container.pump();
    expect(container.read(currentAccountIdProvider), _account.id);
  });

  testWidgets('a replacement account starts its own sync scheduler', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _ChangingAuth()..currentUser = _account;
    final syncedAccounts = <String?>[];
    final databases = <AppDatabase>[];
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
        networkSignalProvider.overrideWithValue(const _NoNetworkEvents()),
        // This test is about which account a scheduler belongs to, and the
        // sync itself is already a recording stub below. Left real, the api
        // points at its development default and the reference-data fetch keeps
        // the tree busy for as long as pumpAndSettle is willing to wait.
        remoteLedgerApiProvider.overrideWithValue(null),
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentAccountIdProvider);
          final db = AppDatabase(NativeDatabase.memory());
          // Not seeded: this test never creates a group, so it never touches
          // the currency foreign key -- and the override has to be synchronous.
          databases.add(db);
          return db;
        }),
        syncControllerProvider.overrideWith(
          () => _RecordingSync(syncedAccounts),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.events.close();
      for (final db in databases) {
        await tester.runAsync(db.close);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(syncedAccounts, [_account.id]);

    auth.currentUser = _otherAccount;
    auth.events.add(auth.currentUser);
    await tester.pumpAndSettle();

    expect(syncedAccounts, [_account.id, _otherAccount.id]);

    // Token refresh and profile edits keep the same ledger and scheduler.
    final scheduler = container.read(syncSchedulerProvider);
    auth.currentUser = Account(
      id: 'other-account',
      isAnonymous: false,
      displayName: 'Updated name',
      email: null,
    );
    auth.events.add(auth.currentUser);
    await tester.pumpAndSettle();
    expect(container.read(syncSchedulerProvider), same(scheduler));
    expect(syncedAccounts, [_account.id, _otherAccount.id]);

    auth.currentUser = null;
    auth.events.add(null);
    await tester.pumpAndSettle();
    expect(container.read(syncSchedulerProvider), isNull);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('sign-in and refresh discover groups on an empty device', () async {
    final auth = _ChangingAuth()..emitOnVerify = true;
    final server = FakeRemoteLedger()
      ..profileId = _account.id
      ..profileId = _account.id;
    final reports = <SyncReport>[];
    final db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        remoteLedgerApiProvider.overrideWithValue(server),
        syncEngineProvider.overrideWith((ref) {
          final engine = _RecordingEngine(
            reports,
            db: ref.watch(appDatabaseProvider),
            remote: ref.watch(remoteLedgerApiProvider)!,
            outbox: ref.watch(outboxQueueProvider),
          );
          ref.onDispose(engine.dispose);
          return engine;
        }),
        appDatabaseProvider.overrideWith((ref) {
          expect(ref.watch(currentAccountIdProvider), _account.id);
          return db;
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.events.close();
      await db.close();
    });
    await _publishGroup(server, 'first', 'Existing home');
    container.listen(accountProvider, (_, _) {});
    await container.read(accountProvider.future);
    expect(container.read(currentAccountIdProvider), isNull);

    await container
        .read(accountControllerProvider.notifier)
        .verifyEmailCode(
          email: 'person@example.com',
          code: '01234567',
          flow: EmailFlow.signInPending,
        );
    expect(reports, isNotEmpty);
    expect(
      reports.every((report) => report.isClean),
      isTrue,
      reason: '$reports',
    );
    expect((await db.select(db.groups).get()).map((group) => group.id), [
      'first',
    ]);

    // The phone adds another group after this device's first successful pull.
    await _publishGroup(server, 'second', 'New group from phone');
    await container.read(syncControllerProvider.notifier).syncAll();
    expect(reports.last.isClean, isTrue, reason: '${reports.last}');
    expect(
      (await db.select(db.groups).get()).map((group) => group.id),
      unorderedEquals(['first', 'second']),
    );
  });

  testWidgets('account changes discard old sync results and retry state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _ChangingAuth()..currentUser = _account;
    final server = FakeRemoteLedger();
    final databases = <AppDatabase>[];
    final oldResult = Completer<SyncReport>();
    final newResult = Completer<SyncReport>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
        remoteLedgerApiProvider.overrideWithValue(server),
        networkSignalProvider.overrideWithValue(const _NoNetworkEvents()),
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentAccountIdProvider);
          final db = AppDatabase(NativeDatabase.memory());
          // Not seeded: this test never creates a group, so it never touches
          // the currency foreign key -- and the override has to be synchronous.
          databases.add(db);
          return db;
        }),
        syncEngineProvider.overrideWith((ref) {
          final account = ref.watch(currentAccountIdProvider);
          return _ControlledEngine(
            account == _account.id ? oldResult.future : newResult.future,
            db: ref.watch(appDatabaseProvider),
            remote: server,
            outbox: ref.watch(outboxQueueProvider),
          );
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.events.close();
      for (final db in databases) {
        await tester.runAsync(db.close);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenSplitApp(),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(container.read(syncControllerProvider).isSyncing, isTrue);
    expect(find.text('No groups yet'), findsNothing);
    expect(tester.takeException(), isNull);

    auth.currentUser = _otherAccount;
    auth.events.add(_otherAccount);
    await tester.pump();
    await tester.pump();
    newResult.complete(const SyncReport(pushed: 0, pulled: 0, failed: 0));
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).hasCompletedFullSync, isTrue);

    oldResult.complete(
      SyncReport(
        pushed: 0,
        pulled: 0,
        failed: 0,
        error: StateError('old account'),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(syncControllerProvider).error, isNull);
    expect(container.read(syncControllerProvider).retryAt, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(Duration.zero);
  });
}

Future<void> _publishGroup(
  FakeRemoteLedger server,
  String id,
  String name,
) async {
  final now = DateTime.utc(2026, 8, 28);
  // One call, because the group and its first member are one change: gating
  // member writes on membership is unsatisfiable for the person creating the
  // group, so the server takes both together or neither.
  await server.seedGroup(
    Group(
      id: id,
      name: name,
      defaultCurrency: 'INR',
      createdBy: '$id-owner',
      createdAt: now,
      isDirect: false,
      simplifyDebts: true,
    ),
    creator: Member(
      id: '$id-owner',
      groupId: id,
      profileId: _account.id,
      displayName: 'Owner',
      joinedAt: now,
    ),
  );
}

class _ChangingAuth implements AuthService {
  late final StreamController<Account?> events =
      StreamController<Account?>.broadcast(
        onListen: () => events.add(currentUser),
      );

  @override
  Account? currentUser;

  bool emitOnVerify = false;

  @override
  Stream<Account?> authStateChanges() => events.stream;

  @override
  Future<IdentityOutcome?> resumeIdentityRedirect() async => null;

  @override
  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    currentUser = _account;
    if (emitOnVerify) events.add(currentUser);
    return SessionKept(account: _account);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}

class _RecordingSync extends SyncController {
  _RecordingSync(this.accounts);

  final List<String?> accounts;

  @override
  Future<void> syncAll() async {
    accounts.add(ref.read(currentAccountIdProvider));
  }
}

class _NoNetworkEvents extends NetworkSignal {
  const _NoNetworkEvents();

  @override
  Stream<bool> get changes => const Stream.empty();
}

class _RecordingEngine extends SyncEngine {
  _RecordingEngine(
    this.reports, {
    required super.db,
    required super.remote,
    required super.outbox,
  });

  final List<SyncReport> reports;

  @override
  Future<SyncReport> syncEverything() async {
    final report = await super.syncEverything();
    reports.add(report);
    return report;
  }
}

class _ControlledEngine extends SyncEngine {
  _ControlledEngine(
    this.result, {
    required super.db,
    required super.remote,
    required super.outbox,
  });

  final Future<SyncReport> result;

  @override
  Future<SyncReport> syncEverything() => result;
}
