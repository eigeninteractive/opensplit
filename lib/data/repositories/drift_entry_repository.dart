import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/activity/entry_events.dart';
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

  /// Writes an entry, its feed line and both queue items as one operation.
  ///
  /// Every local write of an entry goes through here, which is the point: the
  /// activity feed used to be written by a trigger on the server, so an expense
  /// added offline — or by a guest whose backend was unreachable — produced no
  /// history at all, and the one screen that could not answer from the local
  /// database was the one whose entire job was to say what had happened.
  ///
  /// [actorId] is a member id, not an account id. Authorship is group-scoped
  /// for the same reason `entries.created_by` is: a placeholder's edits have to
  /// survive them claiming an account later. Null when this device has no
  /// member row in the group, in which case there is nobody to attribute the
  /// write to and no event is recorded — the same case the trigger declined.
  Future<void> _writeWithEvent({
    required Entry? before,
    required Entry after,
    required String? actorId,
    required DateTime at,
  }) async {
    final event = describeEntryWrite(
      before: before,
      after: after,
      actorId: actorId,
      id: _uuid.v4(),
      at: at,
    );

    await writeEntryLocally(_db, after, event: event);
    await _enqueue(after.id);
    if (event != null) {
      await outbox?.enqueue(OutboxTarget.event, event.id);
    }
  }

  /// How many live entries this device holds, across every group.
  ///
  /// Counted in SQL rather than by reading every row and taking the length of
  /// the result — this is watched for as long as the app is open, and the
  /// caller only ever compares it against a small number.
  Stream<int> watchTotalCount() => _liveCount().watchSingle();

  /// The same count, once.
  ///
  /// Asked before signing in as somebody else, to say how many expenses that
  /// would leave behind — so it is a number in a warning, never a list.
  Future<int> countLiveEntries() => _liveCount().getSingle();

  Selectable<int> _liveCount() {
    final total = _db.entries.id.count();
    final query = _db.selectOnly(_db.entries)
      ..addColumns([total])
      ..where(_db.entries.deletedAt.isNull());
    return query.map((row) => row.read(total) ?? 0);
  }

  /// Hydrates specific entries, in the order asked for.
  ///
  /// Ids the group no longer holds are skipped rather than reported: the caller
  /// is a search whose id list came from a query that has since moved on.
  Future<List<Entry>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(
      _db.entries,
    )..where((t) => t.id.isIn(ids))).get();

    final byId = {for (final entry in await _hydrate(rows)) entry.id: entry};
    return [for (final id in ids) ?byId[id]];
  }

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
    final at = now ?? _clock();
    final entry = composeEntry(
      draft,
      id: _uuid.v4(),
      createdBy: createdBy,
      now: at,
    );

    await _unarchive(entry.groupId);
    // The author is whoever recorded it, which is exactly what createdBy is.
    await _writeWithEvent(
      before: null,
      after: entry,
      actorId: createdBy,
      at: at,
    );
    return entry;
  }

  /// A group somebody is still using is not dormant.
  ///
  /// `upsert_entry` does the same thing on the server, and this is the local
  /// half of it. Without it, adding an expense to a group the reaper archived
  /// three months ago leaves the group hidden until the next successful sync —
  /// which offline is never, so the expense would land somewhere the person who
  /// typed it cannot see.
  Future<void> _unarchive(String groupId) async {
    await (_db.update(_db.groups)
          ..where((t) => t.id.equals(groupId) & t.archivedAt.isNotNull()))
        .write(const GroupsCompanion(archivedAt: Value(null)));
  }

  /// Replaces an existing entry's contents, keeping its id and creation
  /// metadata.
  ///
  /// [actorId] is who is making the edit — the member row for this device in
  /// this group — which is not necessarily whoever created the entry. That
  /// distinction is the whole value of the feed: "Priya edited Ravi's expense"
  /// is the line people actually want to see.
  Future<Entry> update(
    String entryId,
    EntryDraft draft, {
    required String? actorId,
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

    await _writeWithEvent(
      before: existing,
      after: recomposed,
      actorId: actorId,
      at: at,
    );
    return recomposed;
  }

  /// Soft delete. The row stays so that a balance which changed can always be
  /// explained, and so the deletion itself can be synced to other devices.
  Future<void> delete(
    String entryId, {
    required String? actorId,
    DateTime? now,
  }) async {
    final existing = await getEntry(entryId);
    if (existing == null) return;

    final at = now ?? _clock();
    // Soft delete, and `updatedAt` moves so the deletion is itself a delta that
    // other devices will pull. A hard delete would simply vanish from their
    // cursor sweep and live on forever on every device that already had it.
    await _writeWithEvent(
      before: existing,
      after: existing.copyWith(deletedAt: at, updatedAt: at),
      actorId: actorId,
      at: at,
    );
  }
}
