import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/network/network_signal.dart';
import '../data/sync/sync_engine.dart';
import 'sync_scheduler.dart';
import 'backend_providers.dart';
import 'local_providers.dart';
import 'sync_coordinator.dart';

export 'sync_coordinator.dart' show SyncStatus;

part 'sync_providers.g.dart';

@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final api = ref.watch(remoteLedgerApiProvider);
  if (api == null) return null;
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    api: api,
    outbox: ref.watch(outboxQueueProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
}

/// Exposes the account's sync coordinator and its observable status.
///
/// Ledger queries remain the source of screen data. Sync status says whether
/// that data has been refreshed, not what the balances or groups should be.
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
      syncAll: engine.syncEverything,
      syncGroup: engine.syncGroup,
    );
    _coordinator = coordinator;
    coordinator.addListener(() => state = coordinator.status);
    ref.onDispose(coordinator.dispose);
    return coordinator.status;
  }

  /// Refreshes a group through the account-scoped coordinator.
  Future<void> syncGroup(String groupId) async {
    await _coordinator?.syncGroup(groupId);
    _refreshExternalWrites();
  }

  /// Syncs every group this account belongs to, including ones this device has
  /// never seen.
  ///
  /// The list comes from the server, not from the local database. Sweeping
  /// local groups only is what made a second device — and a reinstall, and
  /// signing in after clearing browser data — show an empty app forever: the
  /// groups were on the server, readable, and nothing ever asked for them.
  ///
  /// The sweep itself belongs to [SyncEngine.syncEverything], which is the only
  /// place that can drain the outbox once and pull rates and profiles once for
  /// the whole run rather than per group.
  Future<void> syncAll() async {
    await _coordinator?.syncAll();
    _refreshExternalWrites();
  }

  /// Makes writes from an Android background isolate visible to this one.
  ///
  /// The database sync gate can make this run wait behind that isolate. If the
  /// background run advanced the cursor first, this connection's pull then has
  /// no rows to write and Drift has no local statement from which to infer
  /// that its live queries are stale. Re-running them after the gate settles
  /// closes that race for automatic, manual, and notification-triggered sync.
  void _refreshExternalWrites() {
    if (ref.read(currentAccountIdProvider) != null) {
      ref.read(appDatabaseProvider).refreshAfterExternalSync();
    }
  }

  /// Requeues everything the server previously refused and pushes again.
  ///
  /// Whatever made the server say no may have been fixed since — most often by
  /// a membership row that had not landed yet. If it has not, the items simply
  /// fail the same way and are set aside again, which is why this is safe to
  /// offer as a button.
  Future<void> retryFailed() async {
    await ref.read(outboxQueueProvider).retryDeadLetters();
    await syncAll();
  }
}

/// Whether the device has a network, as it changes. See [NetworkSignal].
@Riverpod(keepAlive: true)
NetworkSignal networkSignal(Ref ref) => const NetworkSignal();

/// The thing that decides when a background sync is worth running.
///
/// keepAlive because it outlives every screen: it is started once by the app
/// shell and listens for the rest of the process. See [SyncScheduler] for what
/// the triggers are and why pull-to-refresh and push wakes deliberately do not
/// go through it.
@Riverpod(keepAlive: true)
SyncScheduler? syncScheduler(Ref ref) {
  if (ref.watch(currentAccountIdProvider) == null) return null;
  final scheduler = SyncScheduler(
    sync: () => ref.read(syncControllerProvider.notifier).syncAll(),
    online: ref.watch(networkSignalProvider).changes,
    // Every local write, from every screen, through one wire. See
    // [OutboxQueue.queued] for why this is not a sync call at each save site.
    writes: ref.watch(outboxQueueProvider).queued,
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
}

/// Syncs a group when its screen opens.
///
/// The coordinator owns failures and retries beyond this screen's lifetime.
@riverpod
Future<void> groupSync(Ref ref, String groupId) async {
  await ref.read(syncControllerProvider.notifier).syncGroup(groupId);
}
