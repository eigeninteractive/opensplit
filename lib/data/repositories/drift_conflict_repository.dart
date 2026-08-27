import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../local/database.dart';
import '../sync/wire.dart' show entryFromJson;
import 'mappers.dart';

/// An edit the server refused, and what the expense says instead.
///
/// Both halves, because neither is much use alone: "you put ₹600" only means
/// something next to "it says ₹500", and together they are usually enough to
/// decide whether anything is still owed a person's attention.
class PendingConflict {
  const PendingConflict({
    required this.attempted,
    required this.current,
    required this.rejectedAt,
  });

  /// The expense as this device meant to write it.
  final Entry attempted;

  /// The expense as it stands, which is also what every other device in the
  /// group is showing. Null if it has since been deleted here.
  final Entry? current;

  final DateTime rejectedAt;

  String get entryId => attempted.id;
  String get groupId => attempted.groupId;
}

/// Edits that did not apply because the expense moved underneath them.
///
/// Read and forget, and nothing else. There is deliberately no "apply mine"
/// here: re-doing an edit is the same act as making it, and it belongs on the
/// screen that already does that, against whatever the expense says now.
class DriftConflictRepository {
  const DriftConflictRepository(this._db);

  final AppDatabase _db;

  /// Everything still unacknowledged, newest first.
  ///
  /// A stream, for the same reason the dead letters are one: until this reaches
  /// a screen, the edit is simply gone and the person who made it has no way to
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
      rejectedAt: row.rejectedAt,
    );
  }

  /// Drops the notice for one expense.
  ///
  /// Called when the person dismisses it, and again whenever they edit that
  /// expense — see [DriftEntryRepository]. Editing it is the acknowledgement:
  /// whatever they decided, they have now seen what it says and acted on it.
  Future<void> forget(String entryId) async {
    await (_db.delete(
      _db.entryConflicts,
    )..where((t) => t.entryId.equals(entryId))).go();
  }
}
