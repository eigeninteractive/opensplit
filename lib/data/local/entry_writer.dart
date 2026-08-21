import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
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
Future<void> writeEntryLocally(AppDatabase db, Entry entry) async {
  assert(
    entry.isBalanced,
    'refusing to store an unbalanced entry: ${entry.id}',
  );

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
            algoVersion: Value(entry.algoVersion),
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
  });
}
