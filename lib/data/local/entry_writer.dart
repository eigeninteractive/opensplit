import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../sync/wire.dart' show memberAmountsToJson;
import 'database.dart';

/// Writes an entry and its children atomically.
///
/// Shared by the repository (local edits) and the sync engine (rows arriving
/// from the server) so there is exactly one place that knows how an entry is
/// persisted. Two implementations would be two chances for the balance
/// invariant to be violated in a way the other path never sees.
///
/// Payers and shares are replaced wholesale rather than diffed: it is simpler,
/// and it mirrors what the server's `upsert_entry` does, so the two cannot
/// disagree about what an edit means.
///
/// [snapshot] is this device's provisional record of the write, when there is
/// one to make. It goes in the same transaction as the entry, deliberately: a
/// change and the record of it are one fact, and committing them separately
/// would allow either an expense with no history or history for an expense that
/// was never stored.
///
/// Provisional because the authoritative record is the server's, taken from the
/// row it actually committed. This one exists so the feed is not empty offline,
/// or for a guest with no reachable backend -- which is what it was before the
/// device wrote anything at all. It is never pushed, and it is dropped as soon
/// as the server's account of the same expense arrives.
///
/// Null on the sync path, where snapshots arrive on their own feed already
/// written by the server.
Future<void> writeEntryLocally(
  AppDatabase db,
  Entry entry, {
  EntrySnapshot? snapshot,
}) async {
  // A real check, not an assert. Asserts are stripped from a release build,
  // which left the one invariant this app is actually about — that what was
  // paid, what is owed and the stated amount agree — enforced only in debug.
  // Both producers guarantee it today, `composeEntry` by construction and the
  // server by a deferred constraint trigger, and this is the line that means a
  // third one cannot quietly not. Cheap, too: two sums over a handful of rows.
  //
  // Throwing is the right failure. A row arriving from a sync is applied inside
  // SyncEngine.pull, whose caller reports the error, and refusing it leaves the
  // previous known-good entry in place — where storing it would put a balance on
  // screen that nothing on this device could explain.
  if (!entry.isBalanced) {
    throw StateError(
      'Refusing to store entry ${entry.id}: it does not balance. '
      'amount=${entry.amountMinor}, '
      'paid=${entry.payers.fold(0, (sum, p) => sum + p.amountMinor)}, '
      'owed=${entry.shares.fold(0, (sum, s) => sum + s.amountMinor)}.',
    );
  }

  await db.transaction(() async {
    await db
        .into(db.entries)
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
          ),
        );

    await (db.delete(
      db.entryPayers,
    )..where((t) => t.entryId.equals(entry.id))).go();
    await (db.delete(
      db.entryShares,
    )..where((t) => t.entryId.equals(entry.id))).go();

    await db.batch((batch) {
      batch.insertAll(db.entryPayers, [
        for (final payer in entry.payers)
          EntryPayersCompanion.insert(
            entryId: entry.id,
            memberId: payer.memberId,
            amountMinor: payer.amountMinor,
          ),
      ]);
      batch.insertAll(db.entryShares, [
        for (final share in entry.shares)
          EntrySharesCompanion.insert(
            entryId: entry.id,
            memberId: share.memberId,
            amountMinor: share.amountMinor,
            weightMicros: Value(share.weightMicros),
          ),
      ]);
    });

    if (snapshot != null) await _writeSnapshot(db, snapshot);
  });
}

/// Records what the expense now looks like, as this device sees it.
///
/// insertOrIgnore because the same id can be offered twice -- a retried write,
/// or a re-entrant path -- and a snapshot is never revised, so a row already
/// present is the same row.
Future<void> _writeSnapshot(AppDatabase db, EntrySnapshot snapshot) async {
  await db
      .into(db.entrySnapshots)
      .insert(
        EntrySnapshotsCompanion.insert(
          id: snapshot.id,
          entryId: snapshot.entryId,
          groupId: snapshot.groupId,
          actorId: Value(snapshot.actorId),
          createdAt: snapshot.createdAt,
          description: snapshot.description,
          currency: snapshot.currency,
          amountMinor: snapshot.amountMinor,
          entryDate: snapshot.entryDate,
          splitKind: snapshot.splitKind,
          categoryId: Value(snapshot.categoryId),
          notes: Value(snapshot.notes),
          deletedAt: Value(snapshot.deletedAt),
          payers: jsonEncode(memberAmountsToJson(snapshot.payers)),
          shares: jsonEncode(memberAmountsToJson(snapshot.shares)),
          isProvisional: Value(snapshot.isProvisional),
        ),
        mode: InsertMode.insertOrIgnore,
      );
}
