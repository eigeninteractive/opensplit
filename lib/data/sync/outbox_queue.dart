import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../local/database.dart';

/// The kind of row an outbox item refers to.
enum OutboxTarget { entry, group, member, profile, event }

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
  /// not the row becoming new. Rewriting it was how a second edit could
  /// reorder a row ahead of something it depends on.
  Future<void> enqueue(OutboxTarget target, String targetId) async {
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: idFor(target, targetId),
            operation: target.name,
            targetId: targetId,
            createdAt: _clock(),
          ),
          onConflict: DoUpdate(
            // A fresh change deserves an immediate attempt even if a previous one
            // had been backed off, or set aside as a dead letter: whatever the
            // server refused may be exactly what this edit changed.
            (_) => const OutboxCompanion(
              attempts: Value(0),
              nextAttemptAt: Value(null),
              lastError: Value(null),
              deadLetteredAt: Value(null),
            ),
          ),
        );
  }

  /// Items ready to be attempted now, in an order the server can accept.
  ///
  /// Sorted by dependency, and only then by age. That ordering follows from
  /// what this queue actually holds: an item says "row X is dirty", not "apply
  /// this change at time T" — [SyncEngine] re-reads the row's current state
  /// when it pushes it — and entries carry no cross-entry ordering requirement
  /// of their own. So there is no chronology to preserve here, and the one
  /// constraint that does exist is referential: a group has to exist before the
  /// members that belong to it, and both before any entry that references them,
  /// or the foreign keys and the membership policies reject the write.
  ///
  /// Sorting the other way round — age first, dependency as a tiebreak — is
  /// what shipped, and it inverted on any second edit. Creating a group offline
  /// and then renaming it moved the group behind its own owner, whose push the
  /// server then refused with a permission error it treats as permanent, so the
  /// owner's member row went to the dead letters and every expense in the group
  /// followed it. Dependency first cannot invert, because rank is a property of
  /// the kind of row rather than of when anyone touched it.
  ///
  /// Age still decides within a rank, so paging under [limit] is stable and the
  /// oldest dirty row of a kind goes first.
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
      final byDependency = _pushOrder(
        a.operation,
      ).compareTo(_pushOrder(b.operation));
      if (byDependency != 0) return byDependency;
      return a.createdAt.compareTo(b.createdAt);
    });

    return rows.take(limit).toList();
  }

  /// Where a kind of row sits in the dependency graph.
  ///
  /// A total order over the levels the schema actually has, which is what makes
  /// sorting by it a valid topological sort: activity events reference entries,
  /// entries reference members, members reference groups, and profiles
  /// reference nothing group-scoped at all. There is no edge pointing back up,
  /// so no item ever needs to precede one of a lower rank.
  ///
  /// Events are last on their own rank rather than sharing the entry's. An
  /// event names the entry it describes with a real foreign key, so pushing the
  /// two together would let a feed line reach the server ahead of the expense
  /// it is about and be refused for a row that was moments from existing.
  static int _pushOrder(String operation) => switch (operation) {
    'group' => 0,
    'member' => 1,
    'event' => 3,
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

    return query.watch().asyncMap((rows) async {
      final refusedEntries = {
        for (final row in rows)
          if (row.operation == OutboxTarget.entry.name) row.targetId,
      };
      return Future.wait(
        [
          for (final row in rows)
            if (!await _isEchoOf(row, refusedEntries)) row,
        ].map(_describe),
      );
    });
  }

  /// Whether this failure is a consequence of another one already listed.
  ///
  /// One user action can queue two rows: the expense, and the feed line saying
  /// it was recorded. When the server refuses the expense, the feed line is
  /// refused straight after it for naming an entry the server does not have —
  /// so a single refused save produced two entries in a list whose whole job is
  /// to tell somebody, once, that something they recorded did not travel.
  ///
  /// The expense is the one worth reporting. Retrying still retries both, since
  /// the queue itself keeps them; this only decides what is worth saying.
  Future<bool> _isEchoOf(OutboxRow row, Set<String> refusedEntries) async {
    if (row.operation != OutboxTarget.event.name) return false;
    final event = await (_db.select(
      _db.entryEvents,
    )..where((t) => t.id.equals(row.targetId))).getSingleOrNull();
    return event != null && refusedEntries.contains(event.entryId);
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
      case OutboxTarget.profile:
        return 'Your name and payment details';
      case OutboxTarget.event:
        // Named after the expense rather than the event, because that is the
        // only half of it anybody recognises. "A line in the activity feed"
        // tells the reader nothing about which of their expenses is affected.
        final row = await (_db.select(
          _db.entryEvents,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return 'An activity entry';
        final entry = await (_db.select(
          _db.entries,
        )..where((t) => t.id.equals(row.entryId))).getSingleOrNull();
        final description = entry?.description.trim() ?? '';
        return description.isEmpty
            ? 'The history of an expense'
            : 'The history of $description';
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
