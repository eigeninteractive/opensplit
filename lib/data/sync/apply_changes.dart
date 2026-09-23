/// Writing one page of a group's history into the local database.
///
/// This replaced five `ChangeFeed` implementations, one per table, each with
/// its own cursor and its own idea of what a page meant. They existed because
/// the old backend could only be paged one table at a time; a group's Durable
/// Object answers for all of them at once, so there is one page and one
/// function that applies it.
///
/// ## There is no last-write-wins comparison here
///
/// There used to be, and it was load-bearing: `remoteWins(local, remote)`
/// compared two `updated_at` timestamps, because a pull could arrive carrying
/// a row older than a local edit that had not been pushed yet.
///
/// A sequence cursor removes the question rather than answering it better.
/// Every row in a page has a number strictly greater than the cursor, so it
/// *is* what the server currently holds — there is no older-or-newer to decide.
/// The one reason not to apply a row is a local edit the outbox has not sent,
/// and that was never a question about clocks: it is a question about intent,
/// which [_dirtyIds] answers exactly. The old code had both and said so in a
/// comment; now it has only the one that was ever right.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/profile.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import 'outbox_queue.dart';
import 'remote_ledger_api.dart';

/// Rows this device means to change and has not managed to push.
///
/// Protected by intent, never by comparing device clocks. A pull is allowed to
/// arrive after a local edit — the cursor only says the server changed
/// something, and knows nothing about what this device did meanwhile.
Future<Set<String>> _dirtyIds(AppDatabase db, OutboxTarget target) async {
  final rows = await (db.select(
    db.outbox,
  )..where((t) => t.operation.equals(target.name))).get();
  return {for (final row in rows) row.targetId};
}

/// Applies one page and advances the group's cursor, in one transaction.
///
/// Returns how many expenses changed, which is what the caller reports as work
/// done. The caller must not open a transaction around this: it opens its own,
/// because the cursor and the rows it accounts for have to commit together or
/// a crash between them re-reads or skips a page.
Future<int> applyGroupChanges(
  AppDatabase db,
  GroupChanges page, {
  required DateTime now,
}) async {
  if (page.purgedAt != null) {
    // The group was archived, went a year silent while settled, and was
    // collected. Everything about it is gone on the server, and this is the
    // one page that says so — the old backend deleted its rows and told
    // nobody, leaving a copy on every device that had ever synced it.
    await db.transaction(() async {
      await (db.delete(
        db.groups,
      )..where((t) => t.id.equals(page.groupId))).go();
      await (db.delete(
        db.groupCursors,
      )..where((t) => t.groupId.equals(page.groupId))).go();
    });
    return 0;
  }

  return db.transaction(() async {
    await _applyGroup(db, page);
    await _applyMembers(db, page);
    final entries = await _applyEntries(db, page);
    await _applyEvents(db, page);

    await db
        .into(db.groupCursors)
        .insertOnConflictUpdate(
          GroupCursorsCompanion.insert(
            groupId: page.groupId,
            seq: Value(page.seq),
            lastSyncedAt: Value(now),
          ),
        );

    return entries;
  });
}

Future<void> _applyGroup(AppDatabase db, GroupChanges page) async {
  final group = page.group;
  if (group == null) return;

  final dirty = await _dirtyIds(db, OutboxTarget.group);
  if (dirty.contains(group.id)) return;

  await db
      .into(db.groups)
      .insertOnConflictUpdate(
        GroupsCompanion.insert(
          id: group.id,
          name: group.name,
          defaultCurrency: group.defaultCurrency,
          isDirect: Value(group.isDirect),
          simplifyDebts: Value(group.simplifyDebts),
          createdBy: Value(group.createdBy),
          createdAt: group.createdAt,
          archivedAt: Value(group.archivedAt),
          seq: Value(group.seq),
        ),
      );
}

Future<void> _applyMembers(AppDatabase db, GroupChanges page) async {
  if (page.members.isEmpty) return;

  final dirty = await _dirtyIds(db, OutboxTarget.member);
  final winners = [
    for (final member in page.members)
      if (!dirty.contains(member.id)) member,
  ];
  if (winners.isEmpty) return;

  await db.batch((batch) {
    for (final member in winners) {
      final row = MembersCompanion.insert(
        id: member.id,
        groupId: member.groupId,
        profileId: Value(member.profileId),
        displayName: member.displayName,
        joinedAt: member.joinedAt,
        leftAt: Value(member.leftAt),
        upiVpa: Value(member.upiVpa),
        seq: Value(member.seq),
      );
      // DO UPDATE, never REPLACE. SQLite implements REPLACE as a delete
      // followed by an insert, and entry_payers.member_id references this
      // table with no cascade — so replacing a member would either fail the
      // foreign key or take an expense's shares with it.
      batch.insert(db.members, row, onConflict: DoUpdate((_) => row));
    }
  });
}

/// Members land before expenses because payers and shares reference them and
/// the local foreign keys are real.
Future<int> _applyEntries(AppDatabase db, GroupChanges page) async {
  if (page.entries.isEmpty) return 0;

  final dirty = await _dirtyIds(db, OutboxTarget.entry);
  var applied = 0;

  for (final entry in page.entries) {
    if (dirty.contains(entry.id)) continue;
    await writeEntryInTransaction(db, entry);
    applied++;
  }
  return applied;
}

Future<void> _applyEvents(AppDatabase db, GroupChanges page) async {
  if (page.events.isEmpty) return;

  await db.batch((batch) {
    for (final event in page.events) {
      batch.insert(
        db.groupEvents,
        GroupEventsCompanion.insert(
          id: event.id,
          groupId: page.groupId,
          actorId: Value(event.actorId),
          createdAt: event.createdAt,
          kind: event.kind.wireName,
          subjectId: Value(event.subjectId),
          payload: jsonEncode(event.payload),
          seq: Value(event.seq),
          ordinal: Value(event.ordinal),
        ),
        // An event is never revised, so a row already here is the same row
        // arriving twice.
        mode: InsertMode.insertOrIgnore,
      );
    }
  });

  // The server's account of these subjects has arrived, so this device's
  // guesses about them are spent.
  //
  // Superseded rather than merged, and per subject rather than per row: five
  // edits made offline are five provisional lines here and one event on the
  // server, which deduped them. Keeping ours alongside would show the same
  // change twice, in two voices, one of which nobody else can see.
  //
  // Scoped to the subjects actually pulled, so a provisional line for an
  // expense whose push was refused outright stays exactly where it is — which
  // is the one case where it is the only record there is.
  final touched = {
    for (final event in page.events) event.subjectId,
  }.nonNulls.toSet();
  touched.removeAll(await _dirtyIds(db, OutboxTarget.entry));
  await (db.delete(
    db.groupEvents,
  )..where((t) => t.subjectId.isIn(touched) & t.isProvisional)).go();

  // Events whose subject is the group itself — a rename, an archive — have no
  // subject id to match on, so they are superseded by kind instead. There is
  // at most one provisional row per kind in practice, because the local write
  // that produced it is the same write the server is now confirming.
  final groupKinds = {
    for (final event in page.events)
      if (event.subjectId == null) event.kind.wireName,
  };
  if (groupKinds.isNotEmpty) {
    await (db.delete(db.groupEvents)..where(
          (t) =>
              t.groupId.equals(page.groupId) &
              t.kind.isIn(groupKinds) &
              t.isProvisional,
        ))
        .go();
  }
}

/// Profiles, which are the one feed still cursored on a timestamp.
///
/// Honestly so: they live in a database several requests write concurrently,
/// so there is nothing there that can issue a sequence number. This is where
/// the last-write-wins comparison survives, because for this feed the question
/// it answers is still a real one.
Future<int> applyProfiles(AppDatabase db, List<Profile> rows) async {
  if (rows.isEmpty) return 0;

  final dirty = await _dirtyIds(db, OutboxTarget.profile);
  final ids = [for (final profile in rows) profile.id];
  final locals = await (db.select(
    db.profiles,
  )..where((t) => t.id.isIn(ids))).get();
  final byId = {for (final local in locals) local.id: local};

  final winners = [
    for (final profile in rows)
      if (!dirty.contains(profile.id) &&
          _remoteWins(byId[profile.id]?.updatedAt, profile.updatedAt))
        profile,
  ];
  if (winners.isEmpty) return 0;

  await db.batch((batch) {
    for (final profile in winners) {
      final row = ProfilesCompanion.insert(
        id: profile.id,
        displayName: Value(profile.displayName),
        avatarUrl: Value(profile.avatarUrl),
        upiVpa: Value(profile.upiVpa),
        updatedAt: Value(profile.updatedAt ?? byId[profile.id]?.updatedAt),
      );
      batch.insert(db.profiles, row, onConflict: DoUpdate((_) => row));
    }
  });
  return winners.length;
}

/// Both sides are server timestamps once a row has been pushed, so this is a
/// genuine last-write-wins rather than a race between two devices' clocks.
bool _remoteWins(DateTime? local, DateTime? remote) {
  if (local == null || remote == null) return true;
  return local.isBefore(remote);
}
