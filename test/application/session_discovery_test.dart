@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/repositories/auth_service.dart';
import 'package:test/test.dart';

import '../data/live_backend.dart';
import '../harness.dart';

/// Signing in on an empty device finds the account's groups, against a real
/// Worker. The providers need Flutter's binding, whose test version replaces
/// HTTP with a stub, so the real client is put back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  setUpBackend();

  liveTest('sign-in and refresh discover groups on an empty device', () async {
    // The groups were made on this person's other device.
    final phone = await Device.guest();
    final account = Account(
      id: phone.profileId,
      isAnonymous: true,
      email: null,
      displayName: null,
    );
    final auth = _SigningIn(account);
    final reports = <SyncReport>[];
    final db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        apiClientProvider.overrideWithValue(phone.client),
        syncEngineProvider.overrideWith((ref) {
          final engine = _RecordingEngine(
            reports,
            db: ref.watch(appDatabaseProvider),
            client: ref.watch(apiClientProvider)!,
            outbox: ref.watch(outboxQueueProvider),
          );
          ref.onDispose(engine.dispose);
          return engine;
        }),
        appDatabaseProvider.overrideWith((ref) {
          expect(ref.watch(currentAccountIdProvider), account.id);
          return db;
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.events.close();
      await db.close();
    });
    final first = await _publishGroup(phone, 'Existing home');
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
    expect(reports.every((r) => r.isClean), isTrue, reason: '$reports');
    expect((await db.select(db.groups).get()).map((group) => group.id), [
      first,
    ]);

    final second = await _publishGroup(phone, 'New group from phone');
    await container.read(syncControllerProvider.notifier).syncAll();
    expect(reports.last.isClean, isTrue, reason: '${reports.last}');
    expect(
      (await db.select(db.groups).get()).map((group) => group.id),
      unorderedEquals([first, second]),
    );
  }, tags: ['integration']);
}

/// A group made and pushed on [device]; its id.
Future<String> _publishGroup(Device device, String name) async {
  final created = await device.groups.createGroup(
    name: name,
    defaultCurrency: 'INR',
    creatorDisplayName: 'Owner',
    creatorProfileId: device.profileId,
  );
  await device.sync.syncGroup(created.group.id);
  return created.group.id;
}

/// Signs in as [account] when a code is verified.
class _SigningIn implements AuthService {
  _SigningIn(this.account);

  final Account account;

  late final StreamController<Account?> events =
      StreamController<Account?>.broadcast(
        onListen: () => events.add(currentUser),
      );

  @override
  Account? currentUser;

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
    currentUser = account;
    events.add(currentUser);
    return SessionKept(account: account);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}

class _RecordingEngine extends SyncEngine {
  _RecordingEngine(
    this.reports, {
    required super.db,
    required super.client,
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
