import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import 'sync_session.dart';

/// A write the server refused outright, named the way its author would name it.
class FailedWrite {
  const FailedWrite({
    required this.target,
    required this.label,
    required this.reason,
    required this.failedAt,
  });

  final OutboxTarget target;

  /// What the user called it: an expense description, a group or member name.
  final String label;

  /// What the server said, verbatim. Paraphrasing it would be guessing at a
  /// cause, and the raw message is the only thing that makes a report useful.
  final String reason;

  final DateTime failedAt;
}

/// Pending local writes waiting to reach the server.
class OutboxQueue {
  OutboxQueue(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  final _queued = StreamController<void>.broadcast();

  /// Fires whenever a local write joins the queue.
  Stream<void> get queued => _queued.stream;

  Future<void> dispose() => _queued.close();

  /// Longest a failing item waits between attempts.
  static const Duration maxBackoff = Duration(minutes: 5);

  /// Marks [targetId] as dirty, coalescing with any item already waiting for
  /// the same row.
  Future<void> enqueue(OutboxTarget target, String targetId) async {
    if (!(await readSyncSession(_db)).enabled) {
      throw StateError('This account session has ended.');
    }
    final revision = const Uuid().v4();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            target: target,
            targetId: targetId,
            revision: revision,
            createdAt: _clock(),
          ),
          onConflict: DoUpdate(
            // A fresh change deserves an immediate attempt even if a previous
            // one had been backed off, or set aside as a dead letter: whatever
            // the server refused may be exactly what this edit changed.
            (_) => OutboxCompanion(
              revision: Value(revision),
              attempts: Value(0),
              nextAttemptAt: Value(null),
              lastError: Value(null),
              deadLetteredAt: Value(null),
            ),
          ),
        );

    if (_queued.hasListener) _queued.add(null);
  }

  /// Items ready to be attempted now, in an order the server can accept.
  Future<List<OutboxRow>> due({int limit = 100}) async {
    final now = _clock();
    final rows = await _pendingInPushOrder();
    // A deferred group or member is a barrier for its dependants. Filtering
    // by deadline before sorting could send a member before its group's retry.
    return rows
        .takeWhile((row) => !(row.nextAttemptAt?.isAfter(now) ?? false))
        .take(limit)
        .toList();
  }

  Future<List<OutboxRow>> _pendingInPushOrder() async {
    final rows = await (_db.select(
      _db.outbox,
    )..where((t) => t.deadLetteredAt.isNull())).get();

    rows.sort((a, b) {
      final byKind = a.target.index.compareTo(b.target.index);
      return byKind != 0 ? byKind : a.createdAt.compareTo(b.createdAt);
    });

    return rows;
  }

  /// Items still expected to reach the server. Dead letters are excluded.
  Future<int> pendingCount() async {
    final rows = await (_db.select(
      _db.outbox,
    )..where((t) => t.deadLetteredAt.isNull())).get();
    return rows.length;
  }

  /// The next eligible write's retry time, or `null` if none remain.
  Future<DateTime?> nextAttemptAt() async {
    final row = (await _pendingInPushOrder()).firstOrNull;
    return row == null ? null : row.nextAttemptAt ?? _clock();
  }

  /// Whether leaving this account would strand an edit held only here.
  Future<bool> hasUnresolvedWrites() async {
    final pending = await (_db.select(_db.outbox)..limit(1)).get();
    if (pending.isNotEmpty) return true;
    return (await (_db.select(_db.entryConflicts)..limit(1)).get()).isNotEmpty;
  }

  /// Writes the server refused outright.
  Future<List<OutboxRow>> deadLetters() => (_db.select(
    _db.outbox,
  )..where((t) => t.deadLetteredAt.isNotNull())).get();

  /// The same, described, and as they happen.
  Stream<List<FailedWrite>> watchDeadLetters() {
    final query = _db.select(_db.outbox)
      ..where((t) => t.deadLetteredAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.deadLetteredAt)]);

    return query.watch().asyncMap((rows) => Future.wait(rows.map(_describe)));
  }

  Future<FailedWrite> _describe(OutboxRow row) async {
    return FailedWrite(
      target: row.target,
      label: await _labelFor(row.target, row.targetId),
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
      case OutboxTarget.profile:
        return 'Your name and payment details';
    }
  }

  /// Puts refused writes back in the queue.
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

  /// The item exactly as [item] read it. A response for an older edit must
  /// not complete or back off a newer one queued during the upload, and the
  /// revision is what tells them apart.
  Expression<bool> _sameEdit($OutboxTable t, OutboxRow item) =>
      t.target.equalsValue(item.target) &
      t.targetId.equals(item.targetId) &
      t.revision.equals(item.revision);

  /// Whether an in-flight request still describes the latest local edit.
  Future<bool> isCurrent(OutboxRow item) async =>
      await (_db.select(
        _db.outbox,
      )..where((t) => _sameEdit(t, item))).getSingleOrNull() !=
      null;

  Future<void> complete(OutboxRow item) =>
      (_db.delete(_db.outbox)..where((t) => _sameEdit(t, item))).go();

  /// Records a failed attempt and schedules the next one.
  Future<void> fail(OutboxRow item, String error, {bool permanent = false}) {
    final update = _db.update(_db.outbox)..where((t) => _sameEdit(t, item));
    if (permanent) {
      return update.write(
        OutboxCompanion(
          deadLetteredAt: Value(_clock()),
          lastError: Value(error),
        ),
      );
    }

    final attempts = item.attempts + 1;
    final backoff = Duration(
      seconds: math.min(1 << math.min(attempts, 10), maxBackoff.inSeconds),
    );
    return update.write(
      OutboxCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(_clock().add(backoff)),
        lastError: Value(error),
      ),
    );
  }
}
