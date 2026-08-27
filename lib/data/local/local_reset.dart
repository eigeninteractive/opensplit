import 'database.dart';
import '../sync/sync_session.dart';

/// Clears everything this device holds *about people and money*, leaving
/// reference data alone.
///
/// Called on exactly one path: signing in as an account that already exists,
/// on a device that had been recording anonymously. Those rows belong to the
/// anonymous account — the server has them under that user id, and row-level
/// security will refuse every push made under the new one — so carrying them
/// across is not a migration, it is a set of writes that cannot land. Leaving
/// them on screen would be worse still: a group list where some entries sync
/// and some silently never will.
///
/// So the honest move is to say what will be lost, get an answer, and then
/// genuinely lose it. The caller does the first two.
///
/// Currencies, categories and exchange rates survive. They are reference data,
/// identical for every account, and re-fetching them would only mean a slower
/// first launch on the far side of a sign-in.
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
    // Children first. Foreign keys are on (see the beforeOpen PRAGMA), and
    // entry_payers/entry_shares reference members, which the cascade from
    // groups would otherwise trip over.
    //
    // Every table is named, in order, rather than any of them being left to a
    // cascade. Relying on one is how entry_events came to be missing here: its
    // references had no ON DELETE action, so it refused the delete of the
    // entries it describes and signing out failed on a foreign key as soon as
    // a device had synced any activity at all. The references cascade now, so
    // this list is belt as well as braces — but the list is the part a reader
    // can check against the schema.
    await db.delete(db.entrySnapshots).go();
    await db.delete(db.entryConflicts).go();
    await db.delete(db.entryPayers).go();
    await db.delete(db.entryShares).go();
    await db.delete(db.entries).go();
    await db.delete(db.members).go();
    await db.delete(db.groups).go();

    // Sync bookkeeping. The outbox has to go with the rows it points at, or
    // the first push after signing in would replay a stranger's writes; the
    // cursors have to go or the new account's first pull would start from a
    // position reached under the old one and skip everything before it.
    await db.delete(db.outbox).go();
    await db.delete(db.syncCursors).go();

    // Cached display names and handles, keyed by profile id.
    await db.delete(db.profiles).go();
  });
}
