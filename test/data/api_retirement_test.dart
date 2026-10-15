import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:opensplit/data/auth/better_auth_service.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import '../harness.dart';

/// Exercises Dio's actual error path, including status and envelope decoding.
class _Server implements HttpClientAdapter {
  _Server({this.code = 'update_required', this.status = 410});
  final String code;
  final int status;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString(
      jsonEncode({
        'error': {
          'code': code,
          'message': 'Update OpenSplit.',
          'retry': 'permanent',
        },
      }),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'retirement survives restarting offline and is scoped to the API origin',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = ApiAccess.persisted(
        preferences,
        baseUrl: 'https://example.test',
      );
      first.requireUpdate();
      await Future<void>.delayed(Duration.zero);
      await first.dispose();
      await preferences.reload();
      final restarted = ApiAccess.persisted(
        preferences,
        baseUrl: 'https://example.test/',
      );
      final otherServer = ApiAccess.persisted(
        preferences,
        baseUrl: 'https://other.test',
      );
      addTearDown(restarted.dispose);
      addTearDown(otherServer.dispose);
      expect(restarted.updateRequired, isTrue);
      expect(restarted.requireWritable, throwsA(isA<ApiFailure>()));
      expect(otherServer.updateRequired, isFalse);
    },
  );

  test('retirement keeps a restored account and credential', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SessionStore.load(
      await SharedPreferences.getInstance(),
      vault: MemoryTokenVault(),
    );
    final account = api.Account(
      id: 'owner',
      isAnonymous: false,
      email: 'owner@example.test',
    );
    await store.write(StoredSession(account: account, token: 'saved-token'));
    final access = ApiAccess();
    addTearDown(access.dispose);
    final client = buildApiClient(
      baseUrl: 'https://example.test',
      access: access,
      token: 'saved-token',
    );
    client.dio.httpClientAdapter = _Server();
    addTearDown(() => client.dio.close());
    final auth = BetterAuthService(
      client: client,
      sessions: store,
      restored: store.read(),
    );
    addTearDown(auth.dispose);
    await expectLater(
      fetch(client.getMetaApi().health()),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.currentUser, account);
    expect(store.read()?.account, account);
    expect(store.read()?.token, 'saved-token');
    expect(access.updateRequired, isTrue);
  });
  test(
    'a retired API latches read-only and stops subsequent requests',
    () async {
      final access = ApiAccess();
      addTearDown(access.dispose);
      final client = buildApiClient(
        baseUrl: 'https://example.test',
        access: access,
      );
      final server = _Server();
      client.dio.httpClientAdapter = server;
      addTearDown(() => client.dio.close());
      for (var i = 0; i < 2; i++) {
        await expectLater(
          fetch(client.getMetaApi().health()),
          throwsA(
            isA<ApiFailure>()
                .having((f) => f.isUpdateRequired, 'update', true)
                .having((f) => f.unreachable, 'offline', false),
          ),
        );
      }
      expect(access.updateRequired, isTrue);
      expect(server.requests, 1);
    },
  );

  test('a missing operation does not make the app read-only', () async {
    final access = ApiAccess();
    addTearDown(access.dispose);
    final client = buildApiClient(
      baseUrl: 'https://example.test',
      access: access,
    );
    client.dio.httpClientAdapter = _Server(code: 'not_found', status: 404);
    addTearDown(() => client.dio.close());
    await expectLater(
      fetch(client.getMetaApi().health()),
      throwsA(isA<ApiFailure>()),
    );
    expect(access.updateRequired, isFalse);
  });

  test(
    'retirement preserves every pending edit, including a departure',
    () async {
      final db = await testDatabase();
      addTearDown(db.close);
      final access = ApiAccess();
      addTearDown(access.dispose);
      final outbox = OutboxQueue(db, access: access);
      addTearDown(outbox.dispose);
      final groups = DriftGroupRepository(
        db,
        accountId: 'owner',
        outbox: outbox,
      );
      final entries = DriftEntryRepository(
        db,
        accountId: 'owner',
        outbox: outbox,
      );
      final made = await groups.createGroup(
        name: 'Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Owner',
        creatorProfileId: 'owner',
      );
      await entries.create(
        EntryDraft(
          groupId: made.group.id,
          currency: 'INR',
          amountMinor: 100,
          description: 'Dinner',
          split: EqualSplit([made.creator.id]),
          payerAmounts: {made.creator.id: 100},
        ),
        createdBy: made.creator.id,
      );
      // An acknowledged group with a queued leave. It must not be restored as
      // though the server had rejected that departure.
      await db.update(db.groups).write(const GroupsCompanion(seq: Value(1)));
      await db.update(db.members).write(const MembersCompanion(seq: Value(2)));
      await groups.leaveGroup(memberId: made.creator.id);
      Future<String> snapshot() async => jsonEncode([
        for (final table in [
          'groups',
          'members',
          'entries',
          'entry_payers',
          'entry_shares',
          'group_events',
          'outbox',
        ])
          [
            for (final row
                in await db
                    .customSelect('SELECT * FROM $table ORDER BY 1')
                    .get())
              row.data,
          ],
      ]);
      final before = await snapshot();
      final client = buildApiClient(
        baseUrl: 'https://example.test',
        access: access,
      );
      final server = _Server();
      client.dio.httpClientAdapter = server;
      addTearDown(() => client.dio.close());
      final engine = SyncEngine(
        db: db,
        client: client,
        outbox: outbox,
        access: access,
        accountId: 'owner',
      );
      addTearDown(engine.dispose);
      final report = await engine.syncEverything();
      expect(
        report.error,
        isA<ApiFailure>().having((f) => f.isUpdateRequired, 'update', true),
      );
      expect(report.failed, 0);
      expect(await snapshot(), before);
      expect(server.requests, 1);
      await engine.syncEverything();
      expect(server.requests, 1);
      expect(await snapshot(), before);

      await expectLater(
        groups.createGroup(
          name: 'Blocked',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Owner',
          creatorProfileId: 'owner',
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        await snapshot(),
        before,
        reason: 'the transaction must roll back every new row',
      );
    },
  );
}
