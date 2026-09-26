import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/network/network_signal.dart';
import '../data/sync/sync_engine.dart';
import 'backend_providers.dart';
import 'local_providers.dart';
import 'sync_coordinator.dart';

export 'sync_coordinator.dart' show SyncStatus;

part 'sync_providers.g.dart';

@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    client: client,
    outbox: ref.watch(outboxQueueProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
}

/// Whether this device knows any currencies, fetching them if not.
@Riverpod(keepAlive: true)
Future<bool> referenceData(Ref ref) async {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return true;
  final shared = engine.shared;
  if (await shared.hasReferenceData()) return true;
  await shared.pullReferenceData();
  return shared.hasReferenceData();
}

@Riverpod(keepAlive: true)
NetworkSignal networkSignal(Ref ref) => const NetworkSignal();

/// Sync for the signed-in account: its status, and the ways to ask for one.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  SyncCoordinator? _coordinator;

  @override
  SyncStatus build() {
    final accountId = ref.watch(currentAccountIdProvider);
    final engine = accountId == null ? null : ref.watch(syncEngineProvider);
    _coordinator = null;
    if (engine == null) return const SyncStatus(enabled: false);

    final coordinator = SyncCoordinator(
      syncAll: () => _refreshing(engine.syncEverything()),
      syncGroup: (groupId) => _refreshing(engine.syncGroup(groupId)),
      online: ref.watch(networkSignalProvider).changes,
      // Every local write, from every screen, through one stream.
      writes: ref.watch(outboxQueueProvider).queued,
    );
    _coordinator = coordinator;
    coordinator.addListener(() => state = coordinator.status);
    ref.onDispose(coordinator.dispose);
    coordinator.start();
    return coordinator.status;
  }

  Future<void> syncGroup(String groupId) async =>
      _coordinator?.syncGroup(groupId);

  Future<void> syncAll() async => _coordinator?.syncAll();

  /// Back in the foreground: sync, unless one ran moments ago.
  void resumed() => _coordinator?.resumed();

  Future<void> retryFailed() async {
    await ref.read(outboxQueueProvider).retryDeadLetters();
    await syncAll();
  }

  Future<void> discardFailed() async {
    await ref.read(syncEngineProvider)?.discardRefused();
    await syncAll();
  }

  /// Streams notice writes made through this database on their own; this
  /// covers ones a background isolate made to the same file.
  Future<SyncReport> _refreshing(Future<SyncReport> sync) async {
    final report = await sync;
    if (ref.mounted) ref.read(appDatabaseProvider).refreshAfterExternalSync();
    return report;
  }
}

/// Syncs one group when a screen showing it opens.
@riverpod
Future<void> groupSync(Ref ref, String groupId) async {
  await ref.read(syncControllerProvider.notifier).syncGroup(groupId);
}
