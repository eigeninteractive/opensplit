import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/network/network_signal.dart';
import '../data/sync/sync_engine.dart';
import 'sync_scheduler.dart';
import 'backend_providers.dart';
import 'local_providers.dart';
import 'session_providers.dart';

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

/// Runs sync and reports what happened.
///
/// Deliberately manual rather than a persistent realtime subscription: peak
/// concurrent realtime peers is what a hosted backend bills for, and pushing a
/// wake-up costs nothing. Live subscriptions are reserved for the rare case of
/// two people editing the same group at the same moment.
/// Runs sync on demand.
///
/// Holds no state, and that is deliberate rather than an omission. Nothing on
/// screen is driven by "how the last sync went": every panel is a query over
/// the local database, a pull that cannot reach the server changes nothing
/// visible, and a write the server refuses outright is surfaced by
/// [failedWritesProvider] instead — which outlives any one run, as it has to.
/// A [SyncReport] held here was read by nobody.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  @override
  void build() {}

  /// Whether there is anything to sync to, and anybody to sync as.
  ///
  /// Syncing as nobody would have every request refused by RLS. That is the
  /// ordinary state before somebody has chosen an account, not an error, so it
  /// returns quietly.
  Future<SyncEngine?> _engine() async {
    if (ref.read(sessionControllerProvider) == null) return null;
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return null;
    return engine;
  }

  Future<void> syncGroup(String groupId) async {
    final engine = await _engine();
    await engine?.syncGroup(groupId);
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
    final engine = await _engine();
    await engine?.syncEverything();
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
SyncScheduler syncScheduler(Ref ref) {
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
/// A provider rather than an initState call so it runs once per mount, is
/// cancelled with the screen, and is trivially overridable in tests. Failures
/// are swallowed on purpose: the screen renders entirely from the local
/// database, so a sync that cannot reach the server changes nothing the user
/// can see and must not produce an error surface.
@riverpod
Future<void> groupSync(Ref ref, String groupId) async {
  try {
    await ref.read(syncControllerProvider.notifier).syncGroup(groupId);
  } catch (_) {
    // Offline is the normal case, not an error.
  }
}
