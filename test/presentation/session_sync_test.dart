import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/network/network_signal.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        // In memory, like every other test here.
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentAccountIdProvider);
          final db = AppDatabase(NativeDatabase.memory());
          databases.add(db);
          return db;
        }),
        apiClientProvider.overrideWithValue(null),
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

  testWidgets('a replacement account starts its own sync', (tester) async {
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
        // This test is about which account a scheduler belongs to, and the sync
        // itself is already a recording stub below.
        apiClientProvider.overrideWithValue(null),
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentAccountIdProvider);
          final db = AppDatabase(NativeDatabase.memory());
          // Not seeded: this test never creates a group, so it never touches
          // the currency foreign key -- and the override has to be synchronous.
          databases.add(db);
          return db;
        }),
        syncControllerProvider.overrideWith(
          () => _RecordingStarts(syncedAccounts),
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
    auth.currentUser = Account(
      id: 'other-account',
      isAnonymous: false,
      displayName: 'Updated name',
      email: null,
    );
    auth.events.add(auth.currentUser);
    await tester.pumpAndSettle();
    expect(syncedAccounts, [
      _account.id,
      _otherAccount.id,
    ], reason: 'a renamed account is the same account');

    auth.currentUser = null;
    auth.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('account changes discard old sync results and retry state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _ChangingAuth()..currentUser = _account;
    final databases = <AppDatabase>[];
    final oldResult = Completer<SyncReport>();
    final newResult = Completer<SyncReport>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
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
            client: buildApiClient(baseUrl: 'http://127.0.0.1:1'),
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

/// Records each account the controller is built for, which is when that
/// account's automatic sync starts.
class _RecordingStarts extends SyncController {
  _RecordingStarts(this.accounts);

  final List<String?> accounts;

  @override
  SyncStatus build() {
    final account = ref.watch(currentAccountIdProvider);
    if (account != null) accounts.add(account);
    return const SyncStatus(enabled: false);
  }
}

class _NoNetworkEvents extends NetworkSignal {
  const _NoNetworkEvents();

  @override
  Stream<bool> get changes => const Stream.empty();
}

class _ControlledEngine extends SyncEngine {
  _ControlledEngine(
    this.result, {
    required super.db,
    required super.client,
    required super.outbox,
  });

  final Future<SyncReport> result;

  @override
  Future<SyncReport> syncEverything() => result;
}
