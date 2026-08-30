import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import 'sync_gate_contract.dart';

/// Creates a gate shared by native connections to [database].
SyncGate createPlatformSyncGate(AppDatabase database) =>
    SqliteSyncGate(database);

/// Serializes native isolates with an expiring SQLite lease.
///
/// Android background messages open a second connection and share no Dart
/// memory with the foreground app. A persisted lease is therefore required,
/// but renewal failure belongs to the current run only. A later run gets a
/// clean attempt.
class SqliteSyncGate implements SyncGate {
  SqliteSyncGate(
    this._database, {
    DateTime Function()? clock,
    this.leaseLifetime = const Duration(minutes: 2),
    this.renewalInterval = const Duration(seconds: 30),
    this.waitTimeout = const Duration(seconds: 15),
    this.pollInterval = const Duration(milliseconds: 200),
  }) : _clock = clock ?? DateTime.now;

  static const _leaseName = 'ledger';

  final AppDatabase _database;
  final DateTime Function() _clock;

  /// How long ownership survives if an isolate terminates without cleanup.
  final Duration leaseLifetime;

  /// How often an active isolate extends its ownership.
  final Duration renewalInterval;

  /// How long a caller waits for another native isolate to finish.
  final Duration waitTimeout;

  /// The delay between lease claims while another isolate owns it.
  final Duration pollInterval;

  final String _ownerId = const Uuid().v4();
  String? _owner;
  Object? _lostError;
  StackTrace? _lostStackTrace;
  bool _disposed = false;

  @override
  Future<T> synchronized<T>(Future<T> Function() operation) async {
    if (_disposed) throw StateError('This synchronization gate is disposed.');
    final owner = _ownerId;
    if (!await _waitForLease(owner)) {
      throw TimeoutException(
        'Another isolate is still synchronizing this account.',
        waitTimeout,
      );
    }

    _owner = owner;
    _lostError = null;
    _lostStackTrace = null;
    final stopRenewal = Completer<void>();
    final renewal = _renewWhileHeld(owner, stopRenewal);
    try {
      final result = await operation();
      await assertHeld();
      return result;
    } finally {
      stopRenewal.complete();
      await renewal;
      await _release(owner);
      if (_owner == owner) _owner = null;
    }
  }

  Future<void> _renewWhileHeld(String owner, Completer<void> stop) async {
    while (!stop.isCompleted) {
      await Future.any([Future<void>.delayed(renewalInterval), stop.future]);
      if (!stop.isCompleted) await _renew(owner);
    }
  }

  Future<bool> _waitForLease(String owner) async {
    final elapsed = Stopwatch()..start();
    Object? claimError;
    StackTrace? claimStackTrace;
    do {
      if (_disposed) throw StateError('This synchronization gate is disposed.');
      try {
        if (await _claim(owner)) return true;
        claimError = null;
        claimStackTrace = null;
      } catch (error, stackTrace) {
        claimError = error;
        claimStackTrace = stackTrace;
      }
      await Future<void>.delayed(pollInterval);
    } while (elapsed.elapsed < waitTimeout);
    if (claimError != null) {
      Error.throwWithStackTrace(claimError, claimStackTrace!);
    }
    return false;
  }

  Future<bool> _claim(String owner) async {
    final now = _clock().toUtc();
    final expiresAt = now.add(leaseLifetime);
    final changed = await _database.customUpdate(
      '''
      INSERT INTO sync_leases (name, owner, expires_at)
      VALUES (?, ?, ?)
      ON CONFLICT(name) DO UPDATE SET
        owner = excluded.owner,
        expires_at = excluded.expires_at
      WHERE sync_leases.expires_at <= ?
         OR sync_leases.owner = excluded.owner
      ''',
      variables: [
        Variable.withString(_leaseName),
        Variable.withString(owner),
        Variable.withString(expiresAt.toIso8601String()),
        Variable.withString(now.toIso8601String()),
      ],
      updates: {_database.syncLeases},
    );
    return changed == 1;
  }

  Future<void> _renew(String owner) async {
    try {
      final expiresAt = _clock().toUtc().add(leaseLifetime);
      final changed = await _database.customUpdate(
        'UPDATE sync_leases SET expires_at = ? WHERE name = ? AND owner = ?',
        variables: [
          Variable.withString(expiresAt.toIso8601String()),
          Variable.withString(_leaseName),
          Variable.withString(owner),
        ],
        updates: {_database.syncLeases},
      );
      if (changed != 1) {
        _lostError = StateError('The synchronization lease was lost.');
        _lostStackTrace = StackTrace.current;
      }
    } catch (error, stackTrace) {
      _lostError = error;
      _lostStackTrace = stackTrace;
    }
  }

  @override
  Future<void> assertHeld() async {
    if (_disposed) throw StateError('This synchronization gate is disposed.');
    final error = _lostError;
    if (error != null) {
      Error.throwWithStackTrace(error, _lostStackTrace!);
    }
    final owner = _owner;
    if (owner == null) {
      throw StateError('Synchronization is not currently owned.');
    }
    final lease = await (_database.select(
      _database.syncLeases,
    )..where((row) => row.name.equals(_leaseName))).getSingleOrNull();
    if (lease?.owner != owner || !lease!.expiresAt.isAfter(_clock().toUtc())) {
      throw StateError('The synchronization lease expired.');
    }
  }

  Future<void> _release(String owner) async {
    try {
      await _database.customUpdate(
        'DELETE FROM sync_leases WHERE name = ? AND owner = ?',
        variables: [
          Variable.withString(_leaseName),
          Variable.withString(owner),
        ],
        updates: {_database.syncLeases},
      );
    } catch (_) {
      // A terminated connection leaves only an expiring lease. Cleanup must
      // not replace the operation's useful result with a secondary failure.
    }
  }

  @override
  void dispose() => _disposed = true;
}
