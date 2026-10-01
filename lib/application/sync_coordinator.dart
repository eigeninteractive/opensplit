import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/sync/sync_engine.dart';

@immutable
class SyncStatus {
  const SyncStatus({
    this.enabled = true,
    this.isSyncing = false,
    this.hasCompletedFullSync = false,
    this.lastReport,
    this.retryAt,
  });

  final bool enabled;
  final bool isSyncing;
  final bool hasCompletedFullSync;
  final SyncReport? lastReport;

  /// When the next automatic attempt is due, if one is scheduled.
  final DateTime? retryAt;

  Object? get error => lastReport?.error;
}

/// Decides when to sync, runs one sync at a time, and reports status.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({
    required this._syncAll,
    required this._syncGroup,
    this._online = const Stream.empty(),
    this._writes = const Stream.empty(),
    DateTime Function()? clock,
    this.minimumGap = const Duration(minutes: 2),
    this.writeDelay = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final Future<SyncReport> Function() _syncAll;
  final Future<SyncReport> Function(String) _syncGroup;
  final Stream<bool> _online;
  final Stream<void> _writes;
  final DateTime Function() _clock;
  final Duration minimumGap;
  final Duration writeDelay;

  final _pendingGroups = <String>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _allPending = false;
  bool _disposed = false;
  int _failures = 0;
  DateTime? _lastStarted;
  Future<void>? _active;
  Timer? _retry;
  Timer? _writeTimer;
  SyncStatus _status = const SyncStatus();

  SyncStatus get status => _status;

  /// Listens for triggers and syncs what happened while the app was closed.
  void start() {
    if (_disposed || _subscriptions.isNotEmpty) return;
    _subscriptions
      ..add(
        _online.listen((isOnline) {
          if (isOnline) resumed();
        }),
      )
      ..add(_writes.listen((_) => _writeQueued()));
    unawaited(syncAll());
  }

  /// The app came back to the foreground, or the network came back.
  void resumed() {
    final last = _lastStarted;
    if (last != null && _clock().difference(last) < minimumGap) return;
    unawaited(syncAll());
  }

  Future<void> syncAll() {
    if (_disposed) return Future.value();
    _allPending = true;
    return _begin();
  }

  /// One group, unless nothing has synced cleanly yet: then everything.
  Future<void> syncGroup(String groupId) {
    if (_disposed) return Future.value();
    if (!_status.hasCompletedFullSync || _status.error != null) {
      return syncAll();
    }
    _pendingGroups.add(groupId);
    return _begin();
  }

  void _writeQueued() {
    if (_disposed) return;
    _writeTimer?.cancel();
    _writeTimer = Timer(writeDelay, () => unawaited(syncAll()));
  }

  Future<void> _begin() {
    _retry?.cancel();
    final active = _active;
    if (active != null) return active;
    final completed = Completer<void>();
    _active = completed.future;
    // A screen can ask for a sync during build; status must not change
    // underneath a frame that is still being built.
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
        _lastStarted = _clock();
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
        // One failure ends this pass; the retry is a full sync.
        _allPending = false;
        _pendingGroups.clear();
      }
      _status = SyncStatus(
        isSyncing: true,
        hasCompletedFullSync:
            _status.hasCompletedFullSync || (full && report.error == null),
        lastReport: report,
      );
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
    if (delay != null) _retry = Timer(delay, () => unawaited(syncAll()));
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
    _writeTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
