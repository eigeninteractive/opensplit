import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/entry.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';

/// An edit the server refused, and what the expense says instead.
class PendingConflict {
  const PendingConflict({
    required this.entryId,
    required this.groupId,
    required this.attempted,
    required this.current,
    required this.rejectedAt,
  });

  final String entryId;
  final String groupId;

  /// The expense as this device meant it to look.
  final api.EntrySnapshot attempted;

  /// The expense as it stands, which is also what every other device in the
  /// group is showing. Null if it has since been deleted here.
  final Entry? current;

  final DateTime rejectedAt;
}

/// Edits that did not apply because the expense moved underneath them.
class DriftConflictRepository {
  const DriftConflictRepository(this._db);

  final AppDatabase _db;

  /// Everything still unacknowledged, newest first.
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
      entryId: row.entryId,
      groupId: row.groupId,
      attempted: row.attempted,
      current: live == null
          ? null
          : entryFromRows(live, payers: payers, shares: shares),
      rejectedAt: row.rejectedAt,
    );
  }

  /// Drops the notice for one expense.
  Future<void> forget(String entryId) async {
    await (_db.delete(
      _db.entryConflicts,
    )..where((t) => t.entryId.equals(entryId))).go();
  }
}
