import 'dart:async';

/// Owns exclusive synchronization access for one local account database.
///
/// Implementations match the platform lifecycle. Native isolates coordinate
/// through SQLite, while browser tabs use a browser-owned lock that cannot be
/// stranded by a reload.
abstract interface class SyncGate {
  /// Runs [operation] while this caller exclusively owns synchronization.
  Future<T> synchronized<T>(Future<T> Function() operation);

  /// Verifies that the current operation still owns the gate.
  Future<void> assertHeld();

  /// Stops queued work and prevents new operations from starting.
  FutureOr<void> dispose();
}
