import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../local/database.dart';
import 'mappers.dart';
import '../sync/wire.dart' show entryFromJson;

/// An edit the server refused, and what the expense says now.
///
/// Both halves together, because neither is useful alone: "you wanted this" is
/// meaningless without "and it now says that", and the whole question a person
/// is being asked is which of the two they meant.
class PendingConflict {
  const PendingConflict({
    required this.attempted,
    required this.current,
    required this.reason,
    required this.rejectedAt,
  });

  /// The expense as this device meant to write it.
  final Entry attempted;

  /// The expense as the server has it, which is also what every other device
  /// in the group is showing.
  final Entry? current;

  final String reason;
  final DateTime rejectedAt;

  String get entryId => attempted.id;
  String get groupId => attempted.groupId;

  /// Whether the two disagree about money rather than only about wording.
  ///
  /// The server only refuses when they do, so this is normally true. It can go
  /// false while somebody sits on the review: the other person may have
  /// reverted their own change in the meantime, which turns "decide" into
  /// "there is nothing left to decide".
  bool get stillDisagrees {
    final now = current;
    if (now == null) return true;
    return now.amountMinor != attempted.amountMinor ||
        !_sameAmounts(
          {for (final p in now.payers) p.memberId: p.amountMinor},
          {for (final p in attempted.payers) p.memberId: p.amountMinor},
        ) ||
        !_sameAmounts(
          {for (final s in now.shares) s.memberId: s.amountMinor},
          {for (final s in attempted.shares) s.memberId: s.amountMinor},
        );
  }

  static bool _sameAmounts(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);
}

/// Edits parked because the expense moved underneath them.
///
/// Read-only apart from [forget]. Writing one is [SyncEngine]'s job, and
/// resolving one is an ordinary edit through the entry repository -- there is
/// deliberately no "apply mine" here that could write an expense by a different
/// route than every other write in the app.
class DriftConflictRepository {
  const DriftConflictRepository(this._db);

  final AppDatabase _db;

  /// Everything waiting on a decision, newest first.
  ///
  /// A stream, for the same reason the dead letters are one: until this reaches
  /// a screen the edit is simply gone, and the person who made it has no way to
  /// find out.
  Stream<List<PendingConflict>> watchAll() {
    final query = _db.select(_db.entryConflicts)
      ..orderBy([(t) => OrderingTerm.desc(t.rejectedAt)]);
    return query.watch().asyncMap((rows) => Future.wait(rows.map(_hydrate)));
  }

  Future<PendingConflict?> byEntry(String entryId) async {
    final row = await (_db.select(
      _db.entryConflicts,
    )..where((t) => t.entryId.equals(entryId))).getSingleOrNull();
    return row == null ? null : _hydrate(row);
  }

  Future<PendingConflict> _hydrate(EntryConflictRow row) async {
    final attempted = entryFromJson(
      jsonDecode(row.attempted) as Map<String, dynamic>,
    );

    final live = await (_db.select(
      _db.entries,
    )..where((t) => t.id.equals(row.entryId))).getSingleOrNull();

    final payers = live == null
        ? const <EntryPayerRow>[]
        : await (_db.select(
            _db.entryPayers,
          )..where((t) => t.entryId.equals(row.entryId))).get();
    final shares = live == null
        ? const <EntryShareRow>[]
        : await (_db.select(
            _db.entryShares,
          )..where((t) => t.entryId.equals(row.entryId))).get();

    return PendingConflict(
      attempted: attempted,
      current: live?.toDomain(payers: payers, shares: shares),
      reason: row.reason,
      rejectedAt: row.rejectedAt,
    );
  }

  /// Drops a parked edit, whichever way it was decided.
  ///
  /// Called after "keep theirs", and after "use mine" has been written through
  /// the ordinary edit path. Not called when the write is merely retried and
  /// refused again -- that replaces this row rather than removing it.
  Future<void> forget(String entryId) async {
    await (_db.delete(
      _db.entryConflicts,
    )..where((t) => t.entryId.equals(entryId))).go();
  }
}
