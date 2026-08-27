import 'package:uuid/uuid.dart';

import '../local/database.dart';

/// The persisted generation of an account's local ledger.
Future<({String epoch, bool enabled})> readSyncSession(AppDatabase db) async {
  final row = await (db.select(
    db.syncSessions,
  )..where((t) => t.id.equals('account'))).getSingleOrNull();
  return (epoch: row?.epoch ?? 'initial', enabled: row?.enabled ?? true);
}

/// Invalidates in-flight work before clearing private data.
///
/// The marker survives cleanup and is visible to other tabs and isolates.
/// Only opening an authenticated foreground database enables it again.
Future<void> suspendSyncSession(AppDatabase db) async {
  await db
      .into(db.syncSessions)
      .insertOnConflictUpdate(
        SyncSessionsCompanion.insert(
          id: 'account',
          epoch: const Uuid().v4(),
          enabled: false,
        ),
      );
}
