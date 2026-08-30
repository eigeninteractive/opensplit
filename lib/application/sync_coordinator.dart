import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/sync/sync_engine.dart';

/// The freshness of this session's local view of the account.
@immutable
class SyncStatus {
  const SyncStatus({
    this.enabled = true,
    this.isSyncing = false,
    this.hasCompletedFullSync = false,
    this.lastReport,
    this.retryAt,
  });

  /// Whether an authenticated backend is available.
  final bool enabled;

  /// Whether a foreground sync or its queued follow-up is running.
  final bool isSyncing;

  /// Whether discovery and all group pulls succeeded during this session.
  final bool hasCompletedFullSync;

  /// The most recent operation's result, including refused writes.
  final SyncReport? lastReport;

  /// The next automatic attempt, if any.
  final DateTime? retryAt;

  /// The failure that prevents claiming the local view is current.
  Object? get error => lastReport?.error;
}

/// Coordinates foreground synchronization for one account.
///
/// Screens, lifecycle events and push wakes share this coordinator. Requests
/// arriving during a run are coalesced into a follow-up, not dropped: a new
/// local write may have missed that run's push phase. Database leases in the
/// engine separately protect against background isolates and other tabs.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({
    required this._syncAll,
    required this._syncGroup,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<SyncReport> Function() _syncAll;
  final Future<SyncReport> Function(String) _syncGroup;
  final DateTime Function() _clock;
  final _pendingGroups = <String>{};
  bool _allPending = false;
  bool _disposed = false;
  int _failures = 0;
  Future<void>? _active;
  Timer? _retry;
  SyncStatus _status = const SyncStatus();

  /// The current immutable snapshot observed by the UI.
  SyncStatus get status => _status;

  /// Refreshes the account, including groups this device has never seen.
  Future<void> syncAll() {
    if (_disposed) return Future.value();
    _allPending = true;
    return _start();
  }

  /// Refreshes a group, or the account if it has not synced or needs recovery.
  Future<void> syncGroup(String groupId) {
    if (_disposed) return Future.value();
    if (!_status.hasCompletedFullSync || _status.error != null) {
      return syncAll();
    }
    _pendingGroups.add(groupId);
    return _start();
  }

  Future<void> _start() {
    _retry?.cancel();
    final active = _active;
    if (active != null) return active;
    final completed = Completer<void>();
    _active = completed.future;
    // Batch this event's triggers and publish status asynchronously. A screen
    // opening can request sync during build; it must not mutate another
    // widget's observed state while that frame is still being constructed.
    scheduleMicrotask(() => unawaited(_drain(completed)));
    return completed.future;
  }

  Future<void> _drain(Completer<void> completed) async {
    if (!_disposed) _setStatus(isSyncing: true);
    while (!_disposed && (_allPending || _pendingGroups.isNotEmpty)) {
      final full = _allPending;
      final groupId = full ? null : _pendingGroups.first;
      _allPending = false;
      if (full) {
        _pendingGroups.clear();
      } else {
        _pendingGroups.remove(groupId);
      }

      SyncReport report;
      try {
        report = await (full ? _syncAll() : _syncGroup(groupId!));
      } catch (error, stackTrace) {
        report = SyncReport(
          pushed: 0,
          pulled: 0,
          failed: 0,
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (_disposed) break;
      if (report.error != null) {
        developer.log(
          'Synchronization attempt failed; saved data remains available.',
          name: 'opensplit.sync',
          level: 900,
          error: report.error,
          stackTrace: report.stackTrace,
        );
      }
      _status = SyncStatus(
        isSyncing: true,
        hasCompletedFullSync:
            _status.hasCompletedFullSync || (full && report.error == null),
        lastReport: report,
      );
      if (report.error != null) {
        // One failure ends this sweep. A full retry covers queued group pulls.
        _allPending = false;
        _pendingGroups.clear();
      }
    }
    _active = null;
    if (!_disposed) _scheduleRetry();
    completed.complete();
  }

  void _scheduleRetry() {
    Duration? delay;
    if (_status.error != null) {
      delay = Duration(seconds: math.min(5 * (1 << _failures), 300));
      _failures = math.min(_failures + 1, 6);
    } else {
      _failures = 0;
      final nextPush = _status.lastReport?.nextPushAt;
      if (nextPush != null) {
        delay = Duration(
          milliseconds: math.max(
            nextPush.difference(_clock()).inMilliseconds,
            1000,
          ),
        );
      }
    }
    if (delay != null) {
      _retry = Timer(delay, () => unawaited(syncAll()));
    }
    _setStatus(
      isSyncing: false,
      retryAt: delay == null ? null : _clock().add(delay),
    );
  }

  void _setStatus({required bool isSyncing, DateTime? retryAt}) {
    _status = SyncStatus(
      isSyncing: isSyncing,
      hasCompletedFullSync: _status.hasCompletedFullSync,
      lastReport: _status.lastReport,
      retryAt: retryAt,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}
