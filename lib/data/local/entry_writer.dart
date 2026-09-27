import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' show Payer, Share;

import '../../domain/models/entry.dart';
import 'database.dart';

/// Writes an entry and its children inside the caller's transaction.
Future<void> writeEntryInTransaction(AppDatabase db, Entry entry) async {
  // A real check, not an assert, which a release build strips. Refusing leaves
  // the previous good row in place rather than a balance nothing can explain.
  if (!entry.isBalanced) {
    throw StateError(
      'Refusing to store entry ${entry.id}: it does not balance. '
      'amount=${entry.row.amountMinor}, '
      'paid=${entry.payers.fold(0, (sum, p) => sum + p.amountMinor)}, '
      'owed=${entry.shares.fold(0, (sum, s) => sum + s.amountMinor)}.',
    );
  }

  // As a companion with its nulls stated: a row's own upsert leaves a null
  // column out, and a restore is exactly a column going back to null.
  await db
      .into(db.entries)
      .insertOnConflictUpdate(entry.row.toCompanion(false));
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
  row,
  payers: [
    for (final payer in payers)
      Payer(memberId: payer.memberId, amountMinor: payer.amountMinor),
  ],
  shares: [
    for (final share in shares)
      Share(
        memberId: share.memberId,
        amountMinor: share.amountMinor,
        weightMicros: share.weightMicros,
      ),
  ],
);
