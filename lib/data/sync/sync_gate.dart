import 'dart:async';

import '../local/database.dart';
import 'sync_gate_native.dart'
    if (dart.library.js_interop) 'sync_gate_web.dart'
    as platform;

/// Creates the synchronization gate appropriate for the current platform.
SyncGate createSyncGate(AppDatabase database) =>
    platform.createPlatformSyncGate(database);

/// Owns exclusive synchronization access for one local account database.
abstract interface class SyncGate {
  /// Runs [operation] while this caller exclusively owns synchronization.
  Future<T> synchronized<T>(Future<T> Function() operation);

  /// Verifies that the current operation still owns the gate.
  Future<void> assertHeld();

  /// Stops queued work and prevents new operations from starting.
  FutureOr<void> dispose();
}
