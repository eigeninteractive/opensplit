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
/// Five triggers, and each answers a different question:
///
///   * [start] -- "what happened while the app was closed?"
///   * [resumed] -- the same question, for a phone that was merely backgrounded.
///   * an online transition -- "there is finally a network; drain the queue."
///   * a local write -- "somebody just recorded something; tell the group."
///   * a push wake, and pull-to-refresh, both of which are elsewhere and
///     deliberately bypass this class entirely: one is the server saying
///     something specific changed, the other is a person asking directly, and
///     neither should be rate-limited by a policy about background chatter.
///
/// The write trigger is the one that was missing, and its absence was not
/// subtle once looked for: saving an expense wrote it locally, queued it, and
/// returned to a group screen that was already mounted, so the only automatic
/// sync there was did not re-run. The expense reached nobody until the app was
/// next backgrounded and resumed.
///
/// Injectable everything -- the sync callback, the connectivity stream, the
/// clock -- because the interesting behaviour here is about time and ordering,
/// and neither is testable against a real network or a real `DateTime.now`.
class SyncScheduler {
  SyncScheduler({
    required this._sync,
    required this._online,
    required this._writes,
    DateTime Function()? clock,
    this.minimumGap = const Duration(minutes: 2),
    this.writeDelay = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function() _sync;
  final Stream<bool> _online;

  /// Local writes joining the outbox. See [OutboxQueue.queued].
  final Stream<void> _writes;

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

  /// How long a write waits before its sync starts.
  ///
  /// Long enough to collect the writes of one user action, short enough that
  /// nobody perceives it. Creating a group queues the group and its owner;
  /// saving an expense that unarchives its group queues two rows as well.
  /// Without this, each of those is a separate sync of the whole account.
  ///
  /// Deliberately NOT subject to [minimumGap]. That gap exists to stop a
  /// flapping connection costing thirty syncs; a person pressing Save is not
  /// background chatter, and making them wait two minutes to tell the group is
  /// the bug this trigger exists to fix.
  final Duration writeDelay;

  StreamSubscription<bool>? _subscription;
  StreamSubscription<void>? _writeSubscription;
  Timer? _writeTimer;
  DateTime? _lastRun;
  bool _running = false;
  bool _disposed = false;

  /// A write arrived while a sync was already in flight.
  ///
  /// It cannot simply be dropped the way a duplicate resume can. The run
  /// already going drained the outbox before this row joined it, so nothing
  /// would carry it — which is exactly the "saved here, invisible everywhere
  /// else" state this class exists to prevent. Recorded, and honoured the
  /// moment the current run finishes.
  bool _writePending = false;

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

    _writeSubscription = _writes.listen((_) => _writeQueued());

    // Unthrottled: this is the first sync of the process, so there is no
    // previous one to be too close to.
    _run();
  }

  /// Something was queued locally. Push it, shortly.
  void _writeQueued() {
    if (_disposed) return;
    if (_running) {
      _writePending = true;
      return;
    }
    _writeTimer?.cancel();
    _writeTimer = Timer(writeDelay, () {
      if (_running) {
        _writePending = true;
        return;
      }
      _run();
    });
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
  /// racing on one cursor. A second background trigger is therefore dropped
  /// rather than queued: whatever it was going to do, the run already in
  /// flight is about to do.
  ///
  /// A local write is the exception, and [_writePending] is why. "The run in
  /// flight is about to do it" is false for a row that joined the outbox after
  /// that run had already drained it.
  void _run() {
    if (_running || _disposed) return;
    _running = true;
    _lastRun = _clock();

    // Failure is not reported, and not because it does not matter. Every screen
    // renders from the local database, so a sync that cannot reach the server
    // changes nothing anybody can see -- and a write the server refuses
    // outright is surfaced by the dead-letter list, which outlives any one run.
    // An error surface here would fire every time somebody walked into a lift.
    _sync()
        .whenComplete(() {
          _running = false;
          if (!_writePending) return;
          _writePending = false;
          // Straight back in rather than through the delay: the wait is for
          // collecting a burst, and this one has already waited out a whole
          // sync.
          _run();
        })
        .catchError((_) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    _writeTimer?.cancel();
    _writeTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _writeSubscription?.cancel();
    _writeSubscription = null;
  }
}
