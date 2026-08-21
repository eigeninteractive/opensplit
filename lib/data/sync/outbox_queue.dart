import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../local/database.dart';

/// The kind of row an outbox item refers to.
enum OutboxTarget { entry, group, member }

/// Pending local writes waiting to reach the server.
///
/// Every mutation is written to the local tables first and queued here second.
/// The UI is answered from local state immediately and never waits on a
/// network round trip, which is what makes the app usable with no connection
/// at all — and what keeps "add expense" under the ten seconds it has before
/// people stop bothering.
class OutboxQueue {
  OutboxQueue(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Longest a failing item waits between attempts.
  static const Duration maxBackoff = Duration(minutes: 5);

  static String idFor(OutboxTarget target, String targetId) =>
      '${target.name}:$targetId';

  /// Queues [targetId] for pushing, replacing any pending item for the same
  /// row.
  ///
  /// Replacing rather than appending is what makes repeated offline edits cheap
  /// and keeps the queue bounded by the number of rows touched, not the number
  /// of times they were touched.
  Future<void> enqueue(OutboxTarget target, String targetId) async {
    await _db
        .into(_db.outbox)
        .insertOnConflictUpdate(
          OutboxCompanion.insert(
            id: idFor(target, targetId),
            operation: target.name,
            targetId: targetId,
            createdAt: _clock(),
            // A fresh change deserves an immediate attempt even if a previous
            // one had been backed off.
            attempts: const Value(0),
            nextAttemptAt: const Value(null),
            lastError: const Value(null),
            deadLetteredAt: const Value(null),
          ),
        );
  }

  /// Items ready to be attempted now, in an order the server can accept.
  ///
  /// Oldest first, but ties broken by dependency: a group has to exist before
  /// the members that belong to it, and both before any entry that references
  /// them, or the foreign keys reject the write. Timestamps alone are not
  /// enough to guarantee that — creating a group queues the group and its owner
  /// in the same millisecond.
  Future<List<OutboxRow>> due({int limit = 100}) async {
    final now = _clock();
    final rows =
        await (_db.select(_db.outbox)..where(
              (t) =>
                  t.deadLetteredAt.isNull() &
                  (t.nextAttemptAt.isNull() |
                      t.nextAttemptAt.isSmallerOrEqualValue(now)),
            ))
            .get();

    rows.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      return _rank(a.operation).compareTo(_rank(b.operation));
    });

    return rows.take(limit).toList();
  }

  /// Push order: a row must not reference something the server has not seen.
  static int _rank(String operation) => switch (operation) {
    'group' => 0,
    'member' => 1,
    _ => 2,
  };

  /// Items still expected to reach the server. Dead letters are excluded.
  Future<int> pendingCount() async {
    final rows = await (_db.select(
      _db.outbox,
    )..where((t) => t.deadLetteredAt.isNull())).get();
    return rows.length;
  }

  /// Writes the server refused outright, kept for the debug bundle.
  Future<List<OutboxRow>> deadLetters() => (_db.select(
    _db.outbox,
  )..where((t) => t.deadLetteredAt.isNotNull())).get();

  Future<void> complete(String id) async {
    await (_db.delete(_db.outbox)..where((t) => t.id.equals(id))).go();
  }

  /// Records a failed attempt and schedules the next one.
  ///
  /// A [permanent] failure — a violated invariant, a permission denial — is
  /// set aside rather than retried: retrying cannot change the answer, and a
  /// poisoned item left in the queue would block everything behind it forever.
  /// It is kept, not deleted, so that a write which never reached the server
  /// can still be accounted for.
  Future<void> fail(String id, String error, {bool permanent = false}) async {
    if (permanent) {
      await (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
        OutboxCompanion(
          deadLetteredAt: Value(_clock()),
          lastError: Value(error),
        ),
      );
      return;
    }

    final row = await (_db.select(
      _db.outbox,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    final attempts = row.attempts + 1;
    final backoff = Duration(
      seconds: math.min(1 << math.min(attempts, 10), maxBackoff.inSeconds),
    );

    await (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(_clock().add(backoff)),
        lastError: Value(error),
      ),
    );
  }
}
