/// Devices talking to a real local Worker: `cd server && npm run dev`.
///
/// There is no fake server. Every rule the server enforces is enforced here by
/// the server itself; tests only observe, pause or fail requests on the way
/// out, through [Tap].
///
/// Tests using this skip themselves when no OpenSplit Worker answers at
/// [backendOrigin], and fail instead under `--dart-define=REQUIRE_BACKEND=true`
/// (CI). `--dart-define=API_BASE_URL=...` points them elsewhere.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/invites.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/data/sync/sync_engine.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

const backendOrigin = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

late bool _backendUp;

/// Whether the probe in [setUpBackend] found a Worker.
bool get backendUp => _backendUp;

/// Probes the Worker once for the file: `/api/health` must name OpenSplit, so
/// another project on the same port skips rather than fails.
void setUpBackend() {
  setUpAll(() async {
    try {
      final health = await fetch(
        buildApiClient(
          baseUrl: backendOrigin,
          timeout: const Duration(seconds: 2),
        ).getMetaApi().health(),
      );
      _backendUp = health.service == api.HealthServiceEnum.opensplit;
    } on Object {
      _backendUp = false;
    }
    if (!_backendUp && const bool.fromEnvironment('REQUIRE_BACKEND')) {
      fail('No OpenSplit Worker at $backendOrigin. Run `npm run dev`.');
    }
  });
}

/// A test that needs the Worker, skipped when there is none. [tags] marks it
/// in a file whose other tests do not need one.
void liveTest(
  String description,
  Future<void> Function() body, {
  Object? tags,
}) => test(description, () async {
  if (!_backendUp) {
    markTestSkipped('No OpenSplit Worker at $backendOrigin.');
    return;
  }
  await body();
}, tags: tags);

/// Observes, pauses, fails or answers a device's requests before they leave.
///
/// [before] runs for every request and may wait, or throw a [DioException] to
/// fail it the way the network or the server would. [answer] may return a JSON
/// body to reply with instead of asking the server; the FX tests use it, since
/// rates are a third-party feed a test needs to control.
class Tap extends Interceptor {
  final requests = <RequestOptions>[];
  Future<void> Function(RequestOptions request)? before;
  Object? Function(RequestOptions request)? answer;

  /// How many requests were sent to a path matching [pattern].
  int count(String method, Pattern pattern) => requests
      .where((r) => r.method == method && r.path.contains(pattern))
      .length;

  /// The latest request to a path matching [pattern].
  RequestOptions? last(String method, Pattern pattern) => requests
      .where((r) => r.method == method && r.path.contains(pattern))
      .lastOrNull;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    requests.add(options);
    try {
      await before?.call(options);
      final body = answer?.call(options);
      if (body == null) return handler.next(options);
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: body),
      );
    } on DioException catch (error) {
      handler.reject(error);
    }
  }
}

/// A failure as the network gives it: no response at all.
DioException offline(RequestOptions request) =>
    DioException.connectionError(requestOptions: request, reason: 'offline');

/// A refusal as the server gives it: the error envelope.
DioException refused(
  RequestOptions request, {
  int status = 409,
  api.Retry retry = api.Retry.permanent,
  String message = 'Refused.',
}) => DioException.badResponse(
  statusCode: status,
  requestOptions: request,
  response: Response(
    requestOptions: request,
    statusCode: status,
    data: {
      'error': {'code': 'malformed', 'message': message, 'retry': retry.value},
    },
  ),
);

/// Matches a request to one group's expense endpoint.
bool isUpsert(RequestOptions r) =>
    r.method == 'POST' && RegExp(r'/groups/[^/]+/entries$').hasMatch(r.path);

/// Matches the "which groups am I in" request.
bool isGroupList(RequestOptions r) =>
    r.method == 'GET' && r.path.endsWith('/api/groups');

/// One simulated device: its own local database, and a real session.
class Device {
  Device._(this.client, this.tap, this.profileId, {required this.pageSize})
    : db = AppDatabase(NativeDatabase.memory()) {
    outbox = OutboxQueue(db);
    groups = DriftGroupRepository(db, outbox: outbox);
    entries = DriftEntryRepository(db, outbox: outbox);
    sync = engine(pageSize: pageSize);
  }

  /// A new guest account, holding nothing but the server's reference data.
  static Future<Device> guest({int pageSize = 200}) async {
    final (client, tap) = _client();
    final outcome = await fetch(client.getIdentityApi().signInAsGuest());
    client.setBearerAuth(bearerScheme, outcome.token!);
    return _ready(
      Device._(client, tap, outcome.account.id, pageSize: pageSize),
    );
  }

  /// Another device of the same account: the same session, an empty database.
  static Future<Device> sameAccountAs(Device other, {int pageSize = 200}) {
    final (client, tap) = _client();
    client.setBearerAuth(bearerScheme, other._token);
    return _ready(Device._(client, tap, other.profileId, pageSize: pageSize));
  }

  static (api.OpensplitApi, Tap) _client() {
    final tap = Tap();
    final client = buildApiClient(baseUrl: backendOrigin);
    client.dio.interceptors.add(tap);
    return (client, tap);
  }

  static Future<Device> _ready(Device device) async {
    addTearDown(device.close);
    await device.sync.shared.pullReferenceData();
    return device;
  }

  final api.OpensplitApi client;
  final Tap tap;
  final String profileId;
  final int pageSize;
  final AppDatabase db;
  late final OutboxQueue outbox;
  late final DriftGroupRepository groups;
  late final DriftEntryRepository entries;
  late final SyncEngine sync;

  String get _token =>
      (client.dio.interceptors.whereType<api.BearerAuthInterceptor>().single)
          .tokens[bearerScheme]!;

  Invites get invites => Invites(client);

  /// A second engine on this device, as a background isolate would hold.
  SyncEngine engine({
    int pageSize = 200,
    Duration requestTimeout = const Duration(seconds: 20),
  }) => SyncEngine(
    db: db,
    client: client,
    outbox: outbox,
    pageSize: pageSize,
    requestTimeout: requestTimeout,
  );

  /// Claims [memberId] in a group [host] has pushed, as an invite link does.
  Future<void> claim(Device host, String groupId, String memberId) async {
    final invite = await host.invites.create(groupId, memberId);
    await invites.join(invite.token);
  }

  Future<List<Entry>> ledger(String groupId) =>
      entries.getEntries(groupId, includeDeleted: true);

  /// The expense half of the activity feed.
  Future<List<EntryChanged>> feed(String groupId) async =>
      (await DriftActivityRepository(
        db,
      ).watchGroup(groupId).first).whereType<EntryChanged>().toList();

  Future<void> close() async {
    sync.dispose();
    await outbox.dispose();
    await db.close();
  }
}
