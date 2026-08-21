import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entry_draft.dart';
import '../../domain/models/entry.dart';
import '../../domain/repositories/entry_repository.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Local-first entry storage.
///
/// Writes land here first and are answered immediately; getting them to the
/// server is a separate, later concern. That ordering is the whole offline
/// story — the app is fully usable on a plane, and "add expense" never shows a
/// spinner because there is nothing to wait for.
final class DriftEntryRepository implements EntryRepository {
  DriftEntryRepository(this._db, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Stream<List<Entry>> watchEntries(
    String groupId, {
    bool includeDeleted = false,
  }) {
    // A payer or share row can change without the parent entry row itself being
    // rewritten — a sync applying children, for instance. Declaring all three
    // tables as dependencies means the stream re-emits whenever any of them
    // moves, so a balance on screen can never be stale.
    return _db
        .customSelect(
          'select 1',
          readsFrom: {_db.entries, _db.entryPayers, _db.entryShares},
        )
        .watch()
        .asyncMap((_) => getEntries(groupId, includeDeleted: includeDeleted));
  }

  @override
  Stream<Entry?> watchEntry(String entryId) => _db
      .customSelect(
        'select 1',
        readsFrom: {_db.entries, _db.entryPayers, _db.entryShares},
      )
      .watch()
      .asyncMap((_) => getEntry(entryId));

  @override
  Future<List<Entry>> getEntries(
    String groupId, {
    bool includeDeleted = false,
  }) async {
    final query = _db.select(_db.entries)
      ..where((t) {
        final inGroup = t.groupId.equals(groupId);
        return includeDeleted ? inGroup : inGroup & t.deletedAt.isNull();
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.entryDate),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);

    final rows = await query.get();
    return _hydrate(rows);
  }

  @override
  Future<Entry?> getEntry(String entryId) async {
    final row = await (_db.select(
      _db.entries,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) return null;
    return (await _hydrate([row])).firstOrNull;
  }

  /// Attaches payers and shares to entry rows in two queries rather than 2N.
  Future<List<Entry>> _hydrate(List<EntryRow> rows) async {
    if (rows.isEmpty) return const [];

    final ids = [for (final row in rows) row.id];
    final payerRows = await (_db.select(
      _db.entryPayers,
    )..where((t) => t.entryId.isIn(ids))).get();
    final shareRows = await (_db.select(
      _db.entryShares,
    )..where((t) => t.entryId.isIn(ids))).get();

    final payersByEntry = <String, List<EntryPayerRow>>{};
    for (final payer in payerRows) {
      payersByEntry.putIfAbsent(payer.entryId, () => []).add(payer);
    }
    final sharesByEntry = <String, List<EntryShareRow>>{};
    for (final share in shareRows) {
      sharesByEntry.putIfAbsent(share.entryId, () => []).add(share);
    }

    return [
      for (final row in rows)
        row.toDomain(
          payers: payersByEntry[row.id] ?? const [],
          shares: sharesByEntry[row.id] ?? const [],
        ),
    ];
  }

  @override
  Future<Entry> create(
    EntryDraft draft, {
    required String createdBy,
    DateTime? now,
  }) async {
    // Composed before the transaction opens: if the split does not resolve, no
    // database work has happened and there is nothing to roll back.
    final entry = composeEntry(
      draft,
      id: _uuid.v4(),
      createdBy: createdBy,
      now: now ?? _clock(),
    );

    await _writeEntry(entry, isNew: true);
    return entry;
  }

  @override
  Future<Entry> update(
    String entryId,
    EntryDraft draft, {
    DateTime? now,
  }) async {
    final existing = await getEntry(entryId);
    if (existing == null) {
      throw StateError('Entry $entryId does not exist');
    }

    final at = now ?? _clock();
    // Recomposed rather than patched, so an edit goes through exactly the same
    // validation as a creation. Creation metadata and the client key are
    // preserved: this is the same fact, revised.
    final recomposed = composeEntry(
      draft,
      id: entryId,
      createdBy: existing.createdBy,
      now: at,
      clientKey: existing.clientKey,
    ).copyWith(createdAt: existing.createdAt);

    await _writeEntry(recomposed, isNew: false);
    return recomposed;
  }

  /// Writes an entry and its children atomically.
  ///
  /// Payers and shares are deleted and reinserted wholesale, which is both
  /// simpler than diffing and closer to how the server RPC behaves. The
  /// transaction is what keeps the balance invariant true at every point an
  /// observer could look.
  Future<void> _writeEntry(Entry entry, {required bool isNew}) async {
    assert(entry.isBalanced, 'composeEntry produced an unbalanced entry');

    await _db.transaction(() async {
      await _db
          .into(_db.entries)
          .insertOnConflictUpdate(
            EntriesCompanion.insert(
              id: entry.id,
              groupId: entry.groupId,
              kind: entry.kind,
              description: Value(entry.description),
              categoryId: Value(entry.categoryId),
              currency: entry.currency,
              amountMinor: entry.amountMinor,
              entryDate: entry.entryDate,
              splitKind: entry.splitKind,
              fxRate: Value(entry.fxRate),
              fxSource: Value(entry.fxSource),
              fxAt: Value(entry.fxAt),
              notes: Value(entry.notes),
              createdBy: entry.createdBy,
              createdAt: entry.createdAt,
              updatedAt: entry.updatedAt,
              deletedAt: Value(entry.deletedAt),
              clientKey: Value(entry.clientKey),
              algoVersion: Value(entry.algoVersion),
            ),
          );

      if (!isNew) {
        await (_db.delete(
          _db.entryPayers,
        )..where((t) => t.entryId.equals(entry.id))).go();
        await (_db.delete(
          _db.entryShares,
        )..where((t) => t.entryId.equals(entry.id))).go();
      }

      await _db.batch((batch) {
        batch.insertAll(_db.entryPayers, [
          for (final payer in entry.payers)
            EntryPayersCompanion.insert(
              entryId: entry.id,
              memberId: payer.memberId,
              amountMinor: payer.amountMinor,
            ),
        ]);
        batch.insertAll(_db.entryShares, [
          for (final share in entry.shares)
            EntrySharesCompanion.insert(
              entryId: entry.id,
              memberId: share.memberId,
              amountMinor: share.amountMinor,
              weightMicros: Value(share.weightMicros),
            ),
        ]);
      });
    });
  }

  @override
  Future<void> delete(String entryId, {DateTime? now}) async {
    final at = now ?? _clock();
    // Soft delete, and `updatedAt` moves so the deletion is itself a delta that
    // other devices will pull. A hard delete would simply vanish from their
    // cursor sweep and live on forever on every device that already had it.
    await (_db.update(_db.entries)..where((t) => t.id.equals(entryId))).write(
      EntriesCompanion(deletedAt: Value(at), updatedAt: Value(at)),
    );
  }
}
