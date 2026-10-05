/// Writing one page of a group's history into the local database.
library;

import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../local/database.dart';
import '../local/entry_writer.dart';
import '../local/tables.dart';
import 'wire.dart';

/// Rows this device changed and has not managed to push.
Future<Set<String>> _dirtyIds(AppDatabase db, OutboxTarget target) async {
  final rows = await (db.select(
    db.outbox,
  )..where((t) => t.target.equalsValue(target))).get();
  return {for (final row in rows) row.targetId};
}

/// Which of [ids] this device holds under a group other than [groupId].
///
/// Ids are minted by devices and each group's server only checks them within
/// that group, so a member of one group could reuse an id this device holds
/// in another. Applying it would move that row between groups here; it is
/// skipped instead, and the group it belongs to keeps it.
Future<Set<String>> _heldByOtherGroups(
  AppDatabase db,
  ResultSetImplementation<Table, Object?> table, {
  required GeneratedColumn<String> id,
  required GeneratedColumn<String> owner,
  required String groupId,
  required List<String> ids,
}) async {
  if (ids.isEmpty) return const {};
  final rows =
      await (db.selectOnly(table)
            ..addColumns([id])
            ..where(id.isIn(ids) & owner.equals(groupId).not()))
          .get();
  final held = {for (final row in rows) row.read(id)!};
  for (final skipped in held) {
    _logForeign(groupId, skipped);
  }
  return held;
}

Future<Set<String>> _memberIds(AppDatabase db, String groupId) async => {
  for (final row
      in await (db.selectOnly(db.members)
            ..addColumns([db.members.id])
            ..where(db.members.groupId.equals(groupId)))
          .get())
    row.read(db.members.id)!,
};

void _logForeign(String groupId, String id) => developer.log(
  'Skipped $id in group $groupId: it names a row of another group.',
  name: 'opensplit.sync',
  level: 900,
);

/// Applies one page and advances the group's cursor, in one transaction, so a
/// crash between them can neither re-read nor skip a page.
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
      // Companions with their nulls stated: a data class upserts a null as
      // "leave it", and restoring, rejoining and clearing are all nulls.
      await db
          .into(db.groups)
          .insertOnConflictUpdate(group.toRow().toCompanion(false));
    }

    final dirtyMembers = await _dirtyIds(db, OutboxTarget.member);
    final foreignMembers = await _heldByOtherGroups(
      db,
      db.members,
      id: db.members.id,
      owner: db.members.groupId,
      groupId: groupId,
      ids: [for (final member in page.members) member.id],
    );
    await db.batch((batch) {
      for (final member in page.members) {
        if (dirtyMembers.contains(member.id) ||
            foreignMembers.contains(member.id)) {
          continue;
        }
        final row = member.toRow(groupId).toCompanion(false);
        // DO UPDATE, never REPLACE: SQLite's REPLACE deletes first, and
        // payers and shares reference members without a cascade.
        batch.insert(db.members, row, onConflict: DoUpdate((_) => row));
      }
    });

    final dirtyEntries = await _dirtyIds(db, OutboxTarget.entry);
    final foreignEntries = await _heldByOtherGroups(
      db,
      db.entries,
      id: db.entries.id,
      owner: db.entries.groupId,
      groupId: groupId,
      ids: [for (final entry in page.entries) entry.id],
    );
    final ownMembers = await _memberIds(db, groupId);
    var applied = 0;
    for (final entry in page.entries) {
      if (dirtyEntries.contains(entry.id)) continue;
      final names = [
        for (final payer in entry.payers) payer.memberId,
        for (final share in entry.shares) share.memberId,
      ];
      if (foreignEntries.contains(entry.id) ||
          !names.every(ownMembers.contains)) {
        _logForeign(groupId, entry.id);
        continue;
      }
      await writeEntryInTransaction(db, entry.toEntry(groupId));
      applied++;
    }

    await _applyEvents(db, page, dirtyEntries);
    // The accounts behind the page's places, including one claimed by
    // somebody the profile feed passed long ago.
    await applyProfiles(db, page.profiles);

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
      if (event.kind != api.EventKind.unknownDefaultOpenApi) event,
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

/// Profiles, which arrive on their own feed and on group pages, so a row can
/// arrive older than the copy already held: a newer local `version` wins.
Future<int> applyProfiles(AppDatabase db, List<api.Profile> rows) async {
  if (rows.isEmpty) return 0;

  final dirty = await _dirtyIds(db, OutboxTarget.profile);
  final locals = await (db.select(
    db.profiles,
  )..where((t) => t.id.isIn([for (final row in rows) row.id]))).get();
  final held = {for (final local in locals) local.id: local.version};

  final winners = [
    for (final profile in rows)
      if (!dirty.contains(profile.id) &&
          (held[profile.id] ?? 0) < profile.version)
        profile.toRow().toCompanion(false),
  ];

  await db.batch((batch) {
    for (final row in winners) {
      batch.insert(db.profiles, row, onConflict: DoUpdate((_) => row));
    }
  });
  return winners.length;
}
