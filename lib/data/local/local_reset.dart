import 'database.dart';
import '../sync/sync_session.dart';

/// Clears everything this device holds *about people and money*, leaving
/// reference data alone.
Future<void> forgetLocalLedger(
  AppDatabase db, {
  bool requireSynced = false,
}) async {
  await db.transaction(() async {
    if (requireSynced) {
      final queued = await (db.select(db.outbox)..limit(1)).get();
      final conflicts = await (db.select(db.entryConflicts)..limit(1)).get();
      if (queued.isNotEmpty || conflicts.isNotEmpty) {
        throw StateError(
          'Sync or resolve the changes on this device before signing out.',
        );
      }
    }
    await suspendSyncSession(db);
    // Children first.
    await db.delete(db.groupEvents).go();
    await db.delete(db.entryConflicts).go();
    await db.delete(db.entryPayers).go();
    await db.delete(db.entryShares).go();
    await db.delete(db.entries).go();
    await db.delete(db.members).go();
    await db.delete(db.groups).go();

    // Sync bookkeeping.
    await db.delete(db.outbox).go();
    await db.delete(db.groupCursors).go();

    // Cached display names and handles, keyed by profile id.
    await db.delete(db.profiles).go();
  });
}
