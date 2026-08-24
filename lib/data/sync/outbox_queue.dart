import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../local/database.dart';

/// The kind of row an outbox item refers to.
enum OutboxTarget { entry, group, member }

/// A write the server refused outright, named the way its author would name it.
class FailedWrite {
  const FailedWrite({
    required this.id,
    required this.target,
    required this.label,
    required this.reason,
    required this.failedAt,
  });

  final String id;
  final OutboxTarget target;

  /// What the user called it: an expense description, a group or member name.
  final String label;

  /// What the server said, verbatim. Paraphrasing it would be guessing at a
  /// cause, and the raw message is the only thing that makes a report useful.
  final String reason;

  final DateTime failedAt;
}

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

  /// Writes the server refused outright.
  Future<List<OutboxRow>> deadLetters() => (_db.select(
    _db.outbox,
  )..where((t) => t.deadLetteredAt.isNotNull())).get();

  /// The same, described, and as they happen.
  ///
  /// A stream rather than a one-shot read because this is the only path by
  /// which anyone ever learns that something they recorded is not going to
  /// reach the rest of the group. Until it reaches a screen, the row sits on
  /// this device looking exactly like a saved expense, and the first symptom is
  /// two people reading different balances weeks later.
  Stream<List<FailedWrite>> watchDeadLetters() {
    final query = _db.select(_db.outbox)
      ..where((t) => t.deadLetteredAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.deadLetteredAt)]);

    return query.watch().asyncMap((rows) => Future.wait(rows.map(_describe)));
  }

  Future<FailedWrite> _describe(OutboxRow row) async {
    final target = OutboxTarget.values.byName(row.operation);
    return FailedWrite(
      id: row.id,
      target: target,
      label: await _labelFor(target, row.targetId),
      reason: row.lastError ?? 'The server refused it without saying why.',
      failedAt: row.deadLetteredAt!,
    );
  }

  /// A name for the refused row, or a generic one if it has since been deleted
  /// locally — the outbox outlives what it points at.
  Future<String> _labelFor(OutboxTarget target, String id) async {
    switch (target) {
      case OutboxTarget.entry:
        final row = await (_db.select(
          _db.entries,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        final description = row?.description.trim() ?? '';
        return description.isEmpty ? 'An expense' : description;
      case OutboxTarget.group:
        final row = await (_db.select(
          _db.groups,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row?.name ?? 'A group';
      case OutboxTarget.member:
        final row = await (_db.select(
          _db.members,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row?.displayName ?? 'A member';
    }
  }

  /// Puts refused writes back in the queue.
  ///
  /// "Permanent" only ever meant permanent against the server as it stood: a
  /// membership row that had not been pushed yet, a group the user was removed
  /// from and added back to, an RLS policy since corrected. Those change, and
  /// when they do this is the only thing standing between the write and the
  /// server.
  Future<int> retryDeadLetters() async {
    return (_db.update(
      _db.outbox,
    )..where((t) => t.deadLetteredAt.isNotNull())).write(
      const OutboxCompanion(
        deadLetteredAt: Value(null),
        nextAttemptAt: Value(null),
        lastError: Value(null),
        attempts: Value(0),
      ),
    );
  }

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
