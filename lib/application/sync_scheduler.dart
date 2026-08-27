import 'dart:async';

/// Decides when a sync is worth running, and runs it.
///
/// Everything the app shows comes from the local database, so a sync is never
/// on the critical path of anything a person is doing. That is what makes it
/// safe to run automatically -- and it is also why the triggers were so easy to
/// under-build: nothing visibly breaks without them, it just quietly stops
/// being true. Before this existed the only automatic sync was opening a group
/// screen, so a cold start landed on a group list showing whatever it last knew,
/// and surfacing from a tunnel with a queued expense pushed nothing at all until
/// the user happened to pull down.
///
/// Four triggers, and each answers a different question:
///
///   * [start] -- "what happened while the app was closed?"
///   * [resumed] -- the same question, for a phone that was merely backgrounded.
///   * an online transition -- "there is finally a network; drain the queue."
///   * a push wake, and pull-to-refresh, both of which are elsewhere and
///     deliberately bypass this class entirely: one is the server saying
///     something specific changed, the other is a person asking directly, and
///     neither should be rate-limited by a policy about background chatter.
///
/// Injectable everything -- the sync callback, the connectivity stream, the
/// clock -- because the interesting behaviour here is about time and ordering,
/// and neither is testable against a real network or a real `DateTime.now`.
class SyncScheduler {
  SyncScheduler({
    required this._sync,
    required this._online,
    DateTime Function()? clock,
    this.minimumGap = const Duration(minutes: 2),
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function() _sync;
  final Stream<bool> _online;
  final DateTime Function() _clock;

  /// How long an automatic sync waits after the last one.
  ///
  /// Guards against the case that actually happens: a phone toggling between
  /// wifi and mobile data on a train emits a run of connectivity events, and
  /// backgrounding an app for four seconds to read a notification is a resume.
  /// Neither is news. Two minutes is long enough that a flapping connection
  /// costs one sync rather than thirty, and short enough that nobody notices
  /// they were throttled.
  final Duration minimumGap;

  StreamSubscription<bool>? _subscription;
  DateTime? _lastRun;
  bool _running = false;
  bool _disposed = false;

  /// Begins listening, and syncs once for whatever happened while the app was
  /// not running.
  void start() {
    if (_disposed || _subscription != null) return;

    _subscription = _online.listen((isOnline) {
      // Only the transition INTO connectivity is interesting. Going offline is
      // not something a sync can help with, and reporting the same online
      // state twice is not a transition.
      if (isOnline) _maybeSync();
    });

    // Unthrottled: this is the first sync of the process, so there is no
    // previous one to be too close to.
    _run();
  }

  /// The app came back to the foreground.
  void resumed() => _maybeSync();

  void _maybeSync() {
    final last = _lastRun;
    if (last != null && _clock().difference(last) < minimumGap) return;
    _run();
  }

  /// Never two at once.
  ///
  /// Overlapping runs would have two pushes draining one outbox and two pulls
  /// racing on one cursor. The second is dropped rather than queued: whatever
  /// it was going to do, the run already in flight is about to do.
  void _run() {
    if (_running || _disposed) return;
    _running = true;
    _lastRun = _clock();

    // Failure is not reported, and not because it does not matter. Every screen
    // renders from the local database, so a sync that cannot reach the server
    // changes nothing anybody can see -- and a write the server refuses
    // outright is surfaced by the dead-letter list, which outlives any one run.
    // An error surface here would fire every time somebody walked into a lift.
    _sync().whenComplete(() => _running = false).catchError((_) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
