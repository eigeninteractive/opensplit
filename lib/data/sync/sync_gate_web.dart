import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../local/database.dart';
import 'sync_gate_contract.dart';

/// Creates a gate shared by every OpenSplit tab in this browser profile.
SyncGate createPlatformSyncGate(AppDatabase _) => BrowserSyncGate();

/// Serializes browser tabs through the Web Locks API.
///
/// Ownership belongs to the browser rather than to a database row. Navigating,
/// reloading, closing, or crashing a tab releases its lock as part of document
/// cleanup, so a replacement tab never waits for a stale wall-clock lease.
class BrowserSyncGate implements SyncGate {
  BrowserSyncGate({this.name = 'opensplit-ledger-sync'});

  /// The origin-scoped Web Locks resource name.
  final String name;

  final web.AbortController _abort = web.AbortController();
  bool _held = false;
  bool _disposed = false;

  @override
  Future<T> synchronized<T>(Future<T> Function() operation) async {
    if (_disposed) throw StateError('This synchronization gate is disposed.');

    late T value;
    Object? operationError;
    StackTrace? operationStackTrace;
    var completed = false;

    Future<void> execute(web.Lock _) async {
      _held = true;
      try {
        value = await operation();
        await assertHeld();
        completed = true;
      } catch (error, stackTrace) {
        operationError = error;
        operationStackTrace = stackTrace;
      } finally {
        _held = false;
      }
    }

    final callback = ((web.Lock lock) => execute(lock).toJS).toJS;
    await web.window.navigator.locks
        .request(name, web.LockOptions(signal: _abort.signal), callback)
        .toDart;

    final error = operationError;
    if (error != null) {
      Error.throwWithStackTrace(error, operationStackTrace!);
    }
    if (!completed) {
      throw StateError('The browser released synchronization before it ran.');
    }
    return value;
  }

  @override
  Future<void> assertHeld() async {
    if (_disposed) throw StateError('This synchronization gate is disposed.');
    if (!_held) throw StateError('The browser synchronization lock was lost.');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _abort.abort();
  }
}
