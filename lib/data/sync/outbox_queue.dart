import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';
import 'sync_session.dart';

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
/// Each mutation and its queue item are committed in one local transaction.
/// The UI is answered from local state immediately and never waits on a
/// network round trip, which is what makes the app usable with no connection
/// at all — and what keeps "add expense" under the ten seconds it has before
/// people stop bothering.
class OutboxQueue {
  OutboxQueue(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  final _queued = StreamController<void>.broadcast();

  /// Fires whenever a local write joins the queue.
  ///
  /// The one wire that makes "save" mean "and tell everybody". Every mutation
  /// in the app funnels through [enqueue], so listening here covers expenses,
  /// settlements, group and member edits and your own profile — and covers
  /// whatever is added next without anybody remembering to.
  ///
  /// Carries no payload. A listener's job is to drain the queue, and the queue
  /// already knows what is in it.
  Stream<void> get queued => _queued.stream;

  Future<void> dispose() => _queued.close();

  /// Longest a failing item waits between attempts.
  static const Duration maxBackoff = Duration(minutes: 5);

  static String idFor(OutboxTarget target, String targetId) =>
      '${target.name}:$targetId';

  /// Marks [targetId] as dirty, coalescing with any item already waiting for
  /// the same row.
  ///
  /// Coalescing rather than appending is what makes repeated offline edits
  /// cheap and keeps the queue bounded by the number of rows touched, not the
  /// number of times they were touched. It is also why this queue is a set of
  /// dirty rows rather than a log of operations — see [due].
  ///
  /// [Outbox.createdAt] is deliberately left alone when the row is already
  /// queued: it records when the row first went dirty, and re-dirtying a row is
  /// not the row becoming new. Rewriting it would let a second edit reorder a
  /// row ahead of something it depends on.
  Future<void> enqueue(OutboxTarget target, String targetId) async {
    if (!(await readSyncSession(_db)).enabled) {
      throw StateError('This account session has ended.');
    }
    final revision = const Uuid().v4();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: idFor(target, targetId),
            target: target,
            targetId: targetId,
            revision: revision,
            createdAt: _clock(),
          ),
          onConflict: DoUpdate(
            // A fresh change deserves an immediate attempt even if a previous one
            // had been backed off, or set aside as a dead letter: whatever the
            // server refused may be exactly what this edit changed.
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
  ///
  /// Sorted by the kind of row first ([OutboxTarget]'s order: a group before
  /// its members, members before the entries that name them), then by age.
  /// The queue holds dirty rows rather than a log of changes, so the only
  /// ordering that matters is the reference one. Age first would let a second
  /// edit to a new group move it behind its own creator.
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
  ///
  /// A newly queued write is due now. Reading the persisted deadline also
  /// restores retry scheduling after the app is restarted during backoff.
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
    return FailedWrite(
      id: row.id,
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
  ///
  /// "Permanent" only ever meant permanent against the server as it stood: a
  /// membership row that had not been pushed yet, a group the person was
  /// removed from and added back to, a guard since corrected. Those change,
  /// and when they do this is the only thing standing between the write and
  /// the server.
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

  /// Whether an in-flight request still describes the latest local edit.
  Future<bool> isCurrent(OutboxRow item) async =>
      await (_db.select(_db.outbox)..where(
            (t) => t.id.equals(item.id) & t.revision.equals(item.revision),
          ))
          .getSingleOrNull() !=
      null;

  Future<void> complete(String id, {String? revision}) async {
    await (_db.delete(_db.outbox)..where(
          (t) =>
              t.id.equals(id) &
              (revision == null
                  ? const Constant(true)
                  : t.revision.equals(revision)),
        ))
        .go();
  }

  /// Records a failed attempt and schedules the next one.
  ///
  /// A [permanent] failure — a violated invariant, a permission denial — is
  /// set aside rather than retried: retrying cannot change the answer, and a
  /// poisoned item left in the queue would block everything behind it forever.
  /// It is kept, not deleted, so that a write which never reached the server
  /// can still be accounted for.
  ///
  /// A stale write is neither retried nor kept here — see [EntryConflicts]. It
  /// leaves the queue entirely, because what is left to do about it is not a
  /// send.
  Future<void> fail(
    String id,
    String error, {
    bool permanent = false,
    String? revision,
  }) => _db.transaction(() async {
    final current = await (_db.select(
      _db.outbox,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (current == null || (revision != null && current.revision != revision)) {
      return;
    }
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
  });
}
