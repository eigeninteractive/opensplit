import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import 'database.dart';

/// Writes an entry and its children inside the caller's transaction.
///
/// The one place an entry is persisted, used by local edits and by rows
/// arriving from the server alike. Payers and shares are replaced wholesale,
/// as the server replaces them. The caller writes the outbox item or the sync
/// cursor in the same transaction.
Future<void> writeEntryInTransaction(AppDatabase db, Entry entry) async {
  // A real check, not an assert, which a release build strips. Refusing leaves
  // the previous good row in place rather than a balance nothing can explain.
  if (!entry.isBalanced) {
    throw StateError(
      'Refusing to store entry ${entry.id}: it does not balance. '
      'amount=${entry.amountMinor}, '
      'paid=${entry.payers.fold(0, (sum, p) => sum + p.amountMinor)}, '
      'owed=${entry.shares.fold(0, (sum, s) => sum + s.amountMinor)}.',
    );
  }

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
          seq: Value(entry.seq),
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
}

/// Reassembles an entry from its row and children.
Entry entryFromRows(
  EntryRow row, {
  required List<EntryPayerRow> payers,
  required List<EntryShareRow> shares,
}) => Entry(
  id: row.id,
  groupId: row.groupId,
  kind: row.kind,
  description: row.description,
  categoryId: row.categoryId,
  currency: row.currency,
  amountMinor: row.amountMinor,
  entryDate: row.entryDate,
  splitKind: row.splitKind,
  payers: [
    for (final payer in payers)
      EntryPayer(memberId: payer.memberId, amountMinor: payer.amountMinor),
  ],
  shares: [
    for (final share in shares)
      EntryShare(
        memberId: share.memberId,
        amountMinor: share.amountMinor,
        weightMicros: share.weightMicros,
      ),
  ],
  fxRate: row.fxRate,
  fxSource: row.fxSource,
  fxAt: row.fxAt,
  notes: row.notes,
  createdBy: row.createdBy,
  createdAt: row.createdAt,
  seq: row.seq,
  deletedAt: row.deletedAt,
  clientKey: row.clientKey,
);
