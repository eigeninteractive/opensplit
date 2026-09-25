/// Writing one page of a group's history into the local database.
///
/// Every row in a page carries a sequence number greater than the cursor, so
/// it *is* what the server holds: there is no newer-or-older to decide. The one
/// reason not to apply a row is a local edit still waiting in the outbox
/// ([_dirtyIds]). Such a row is skipped, and the sync engine rewinds the cursor
/// if the server later refuses that edit, so the server's version is read
/// again.
library;

import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/kinds.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import 'wire.dart';

/// Rows this device changed and has not managed to push.
Future<Set<String>> _dirtyIds(AppDatabase db, OutboxTarget target) async {
  final rows = await (db.select(
    db.outbox,
  )..where((t) => t.target.equalsValue(target))).get();
  return {for (final row in rows) row.targetId};
}

/// Applies one page and advances the group's cursor, in one transaction, so
/// a crash between them can neither re-read nor skip a page.
///
/// Returns how many expenses changed.
Future<int> applyGroupChanges(
  AppDatabase db,
  api.ChangePage page, {
  required DateTime now,
}) async {
  final groupId = page.groupId;

  if (page.purgedAt != null) {
    // The group was collected on the server; this page is the one that says so.
    await db.transaction(() async {
      await (db.delete(db.groups)..where((t) => t.id.equals(groupId))).go();
      await (db.delete(
        db.groupCursors,
      )..where((t) => t.groupId.equals(groupId))).go();
    });
    return 0;
  }

  return db.transaction(() async {
    // Foreign-key order: the group, its members, entries naming them, then
    // events naming both.
    final group = page.group;
    if (group != null &&
        !(await _dirtyIds(db, OutboxTarget.group)).contains(group.id)) {
      await db.into(db.groups).insertOnConflictUpdate(group.toRow());
    }

    final dirtyMembers = await _dirtyIds(db, OutboxTarget.member);
    await db.batch((batch) {
      for (final member in page.members) {
        if (dirtyMembers.contains(member.id)) continue;
        final row = member.toRow(groupId);
        // DO UPDATE, never REPLACE: SQLite's REPLACE deletes first, and
        // payers and shares reference members without a cascade.
        batch.insert(db.members, row, onConflict: DoUpdate((_) => row));
      }
    });

    final dirtyEntries = await _dirtyIds(db, OutboxTarget.entry);
    var applied = 0;
    for (final entry in page.entries) {
      if (dirtyEntries.contains(entry.id)) continue;
      await writeEntryInTransaction(db, entry.toEntry(groupId));
      applied++;
    }

    await _applyEvents(db, page, dirtyEntries);

    await db
        .into(db.groupCursors)
        .insertOnConflictUpdate(
          GroupCursorsCompanion.insert(
            groupId: groupId,
            seq: Value(page.seq),
            lastSyncedAt: Value(now),
          ),
        );
    return applied;
  });
}

Future<void> _applyEvents(
  AppDatabase db,
  api.ChangePage page,
  Set<String> dirtyEntries,
) async {
  // A kind this build has never heard of is left out of the feed rather than
  // stored as an unreadable line.
  final events = [
    for (final event in page.events)
      if (event.kind != EventKind.unknownDefaultOpenApi) event,
  ];
  if (events.isEmpty) return;

  await db.batch((batch) {
    for (final event in events) {
      // Events are never revised, so one already here is the same event.
      batch.insert(
        db.groupEvents,
        event.toRow(page.groupId),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });

  // The server's account of these subjects replaces this device's provisional
  // lines about them, except for an entry whose own edit is still unsent.
  final subjects = {
    for (final event in events) event.subjectId,
  }.nonNulls.toSet().difference(dirtyEntries);
  await (db.delete(
    db.groupEvents,
  )..where((t) => t.subjectId.isIn(subjects) & t.isProvisional)).go();

  // Events about the group itself have no subject, so they replace
  // provisional lines of the same kind.
  final groupKinds = {
    for (final event in events)
      if (event.subjectId == null) event.kind,
  };
  if (groupKinds.isNotEmpty) {
    await (db.delete(db.groupEvents)..where(
          (t) =>
              t.groupId.equals(page.groupId) &
              t.kind.isInValues(groupKinds) &
              t.isProvisional,
        ))
        .go();
  }
}

/// Profiles, the one feed still cursored on a timestamp (they live in D1,
/// which has several writers and so no sequence number). Here a newer local
/// `updatedAt` really can mean the remote row is older.
Future<int> applyProfiles(AppDatabase db, List<api.Profile> rows) async {
  if (rows.isEmpty) return 0;

  final dirty = await _dirtyIds(db, OutboxTarget.profile);
  final locals = await (db.select(
    db.profiles,
  )..where((t) => t.id.isIn([for (final row in rows) row.id]))).get();
  final heldAt = {for (final local in locals) local.id: local.updatedAt};

  final winners = [
    for (final profile in rows)
      if (!dirty.contains(profile.id) &&
          _remoteWins(heldAt[profile.id], profile.updatedAt))
        profile.toRow(),
  ];

  await db.batch((batch) {
    for (final row in winners) {
      batch.insert(db.profiles, row, onConflict: DoUpdate((_) => row));
    }
  });
  return winners.length;
}

bool _remoteWins(DateTime? local, DateTime? remote) =>
    local == null || remote == null || local.isBefore(remote);
