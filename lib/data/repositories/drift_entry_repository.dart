import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/activity/snapshot_diff.dart';
import '../../domain/entry_draft.dart';
import '../../domain/models/entry.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group_event.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import '../sync/outbox_queue.dart';

/// Local-first entry storage.
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
  Future<void> _enqueue(String entryId) async =>
      outbox?.enqueue(OutboxTarget.entry, entryId);

  /// Writes an entry, a provisional feed line for it, and its outbox item.
  Future<void> _writeWithSnapshot({
    required Entry after,
    required String? actorId,
    required DateTime at,
  }) async {
    final snapshot = snapshotOf(after);
    final latest = await _latestSnapshot(after.id);

    await writeEntryInTransaction(_db, after);
    if (latest == null || !recordsSameShape(latest, snapshot)) {
      await _db
          .into(_db.groupEvents)
          .insert(
            GroupEventsCompanion.insert(
              id: _uuid.v4(),
              groupId: after.groupId,
              actorId: Value(actorId),
              createdAt: at,
              kind: EventKind.entry,
              subjectId: Value(after.id),
              entry: Value(snapshot),
              isProvisional: const Value(true),
            ),
          );
    }

    // Editing an expense acknowledges any conflict notice about it.
    await (_db.delete(
      _db.entryConflicts,
    )..where((t) => t.entryId.equals(after.id))).go();

    await _enqueue(after.id);
  }

  /// The most recent thing recorded about an entry, from either source.
  Future<api.EntrySnapshot?> _latestSnapshot(String entryId) async {
    final row =
        await (_db.select(_db.groupEvents)
              ..where(
                (t) =>
                    t.subjectId.equals(entryId) &
                    t.kind.equalsValue(EventKind.entry),
              )
              ..orderBy(newestFirst)
              ..limit(1))
            .getSingleOrNull();
    return row?.entry;
  }

  /// How many live entries this device holds, across every group.
  Stream<int> watchTotalCount() => _liveCount().watchSingle();

  /// The same count, once.
  Future<int> countLiveEntries() => _liveCount().getSingle();

  Selectable<int> _liveCount() {
    final total = _db.entries.id.count();
    final query = _db.selectOnly(_db.entries)
      ..addColumns([total])
      ..where(_db.entries.deletedAt.isNull());
    return query.map((row) => row.read(total) ?? 0);
  }

  /// Hydrates specific entries, in the order asked for.
  Future<List<Entry>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(
      _db.entries,
    )..where((t) => t.id.isIn(ids))).get();

    final byId = {for (final entry in await _hydrate(rows)) entry.id: entry};
    return [for (final id in ids) ?byId[id]];
  }

  /// Every entry in a group, most recent first.
  Stream<List<Entry>> watchEntries(
    String groupId, {
    bool includeDeleted = false,
  }) {
    // A payer or share row can change without the parent entry row itself being
    // rewritten — a sync applying children, for instance.
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
        (t) => OrderingTerm(
          expression: t.occurredAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
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
        entryFromRows(
          row,
          payers: payersByEntry[row.id] ?? const [],
          shares: sharesByEntry[row.id] ?? const [],
        ),
    ];
  }

  /// Resolves [draft] into a balanced entry and stores it.
  Future<Entry> create(
    EntryDraft draft, {
    required String createdBy,
    DateTime? now,
  }) async {
    // Composed before the transaction opens: if the split does not resolve, no
    // database work has happened and there is nothing to roll back.
    final at = now ?? _clock();
    final entry = composeEntry(
      draft,
      id: _uuid.v4(),
      createdBy: createdBy,
      now: at,
    );

    await _db.transaction(() async {
      await _unarchive(entry.groupId);
      await _writeWithSnapshot(after: entry, actorId: createdBy, at: at);
    });
    return entry;
  }

  /// A group somebody is still using is not dormant.
  Future<void> _unarchive(String groupId) async {
    await (_db.update(_db.groups)
          ..where((t) => t.id.equals(groupId) & t.archivedAt.isNotNull()))
        .write(const GroupsCompanion(archivedAt: Value(null)));
  }

  /// Replaces an existing entry's contents, keeping its id and creation
  /// metadata.
  Future<Entry> update(
    String entryId,
    EntryDraft draft, {
    required String? actorId,
    DateTime? now,
    Entry? expected,
  }) => _db.transaction(() async {
    final existing = await getEntry(entryId);
    if (existing == null) {
      throw StateError('Entry $entryId does not exist');
    }
    _checkExpected(existing, expected);

    final at = now ?? _clock();
    // Recomposed rather than patched, so an edit goes through exactly the same
    // validation as a creation.
    final recomposed = composeEntry(
      draft,
      id: entryId,
      createdBy: existing.createdBy,
      now: at,
      clientKey: existing.clientKey,
    ).copyWith(createdAt: existing.createdAt, seq: existing.seq);

    await _writeWithSnapshot(after: recomposed, actorId: actorId, at: at);
    return recomposed;
  });

  /// Soft delete. The row stays so that a balance which changed can always be
  /// explained, and so the deletion itself can be synced to other devices.
  Future<void> delete(
    String entryId, {
    required String? actorId,
    DateTime? now,
    Entry? expected,
  }) => _db.transaction(() async {
    final existing = await getEntry(entryId);
    if (existing == null) return;
    _checkExpected(existing, expected);

    final at = now ?? _clock();
    // Soft delete.
    await _writeWithSnapshot(
      after: existing.copyWith(deletedAt: at),
      actorId: actorId,
      at: at,
    );
  });

  void _checkExpected(Entry current, Entry? expected) {
    // An acknowledgement only moves `seq`. It must not invalidate an open
    // form, but an actual local or remote edit must not be overwritten.
    if (expected != null && expected.copyWith(seq: current.seq) != current) {
      throw const StaleEntryException();
    }
  }
}
