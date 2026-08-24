import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entry_draft.dart';
import '../../domain/models/entry.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import '../sync/outbox_queue.dart';
import 'mappers.dart';

/// Local-first entry storage.
///
/// Writes land here first and are answered immediately; getting them to the
/// server is a separate, later concern. That ordering is the whole offline
/// story — the app is fully usable on a plane, and "add expense" never shows a
/// spinner because there is nothing to wait for.
///
/// An entry, its payers and its shares are one atomic fact. They are never
/// written separately — a torn write would leave a row that violates the
/// balance invariant, which is exactly what the server's deferred trigger
/// exists to make impossible.
final class DriftEntryRepository {
  DriftEntryRepository(
    this._db, {
    this.outbox,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// Null in a purely local build, where there is nothing to sync to.
  final OutboxQueue? outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Queues a row for the server.
  ///
  /// Done here rather than left to callers so that no write path can forget:
  /// an entry that is saved locally but never queued would silently never
  /// leave the device.
  Future<void> _enqueue(String entryId) async =>
      outbox?.enqueue(OutboxTarget.entry, entryId);

  /// Every entry in a group, most recent first.
  ///
  /// Returns the whole journal rather than a page: balances are a fold over all
  /// of it, and the fold runs locally on every read. For the group sizes this
  /// app targets that is microseconds, and it is what removes the spinner from
  /// every screen.
  ///
  /// Soft-deleted entries are excluded unless [includeDeleted] is set. The
  /// balance fold ignores them either way; history screens want them.
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

  Stream<Entry?> watchEntry(String entryId) => _db
      .customSelect(
        'select 1',
        readsFrom: {_db.entries, _db.entryPayers, _db.entryShares},
      )
      .watch()
      .asyncMap((_) => getEntry(entryId));

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

  /// Resolves [draft] into a balanced entry and stores it.
  ///
  /// Throws [SplitException] if the draft does not describe a valid entry, in
  /// which case nothing is written.
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

    await writeEntryLocally(_db, entry);
    await _enqueue(entry.id);
    return entry;
  }

  /// Replaces an existing entry's contents, keeping its id and creation
  /// metadata.
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

    await writeEntryLocally(_db, recomposed);
    await _enqueue(recomposed.id);
    return recomposed;
  }

  /// Soft delete. The row stays so that a balance which changed can always be
  /// explained, and so the deletion itself can be synced to other devices.
  Future<void> delete(String entryId, {DateTime? now}) async {
    final at = now ?? _clock();
    // Soft delete, and `updatedAt` moves so the deletion is itself a delta that
    // other devices will pull. A hard delete would simply vanish from their
    // cursor sweep and live on forever on every device that already had it.
    await (_db.update(_db.entries)..where((t) => t.id.equals(entryId))).write(
      EntriesCompanion(deletedAt: Value(at), updatedAt: Value(at)),
    );
    await _enqueue(entryId);
  }
}
