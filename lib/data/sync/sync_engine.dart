import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import '../repositories/mappers.dart';
import 'outbox_queue.dart';
import 'remote_ledger_api.dart';
import 'sync_cursor.dart';

/// What one sync run did.
class SyncReport {
  const SyncReport({
    required this.pushed,
    required this.pulled,
    required this.failed,
    this.error,
  });

  final int pushed;
  final int pulled;
  final int failed;
  final Object? error;

  bool get isClean => failed == 0 && error == null;

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, pulled: $pulled, failed: $failed'
      '${error == null ? '' : ', error: $error'})';
}

/// Moves rows between this device and the server.
///
/// Push first, then pull. That ordering matters: a local write carries a client
/// clock, which must never decide a conflict. Pushing first has the server
/// stamp its own `updated_at`, and the pull that follows brings that
/// authoritative value straight back, so last-write-wins is always comparing
/// two server timestamps and never two devices' opinions of the time.
///
/// Entries are independent facts with no cross-entry ordering requirement,
/// which is the whole reason a cursor over `(updated_at, id)` is sufficient and
/// a CRDT is not needed.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.api,
    required this.outbox,
    DateTime Function()? clock,
    this.pageSize = 200,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final RemoteLedgerApi api;
  final OutboxQueue outbox;
  final DateTime Function() _clock;
  final int pageSize;

  Future<SyncReport> syncGroup(String groupId) async {
    final pushed = await push();
    try {
      final pulled = await pull(groupId);
      return SyncReport(
        pushed: pushed.sent,
        pulled: pulled,
        failed: pushed.failed,
      );
    } catch (error) {
      return SyncReport(
        pushed: pushed.sent,
        pulled: 0,
        failed: pushed.failed,
        error: error,
      );
    }
  }

  /// Drains everything currently due from the outbox.
  Future<({int sent, int failed})> push() async {
    var sent = 0;
    var failed = 0;

    for (final item in await outbox.due()) {
      try {
        await _pushOne(item);
        await outbox.complete(item.id);
        sent++;
      } on RemoteRejected catch (e) {
        // A rejected invariant or a permission failure will be rejected exactly
        // the same way next time. Retrying forever would wedge everything
        // queued behind it, so it is dropped and recorded instead.
        await outbox.fail(item.id, e.message, permanent: e.permanent);
        failed++;
      } catch (e) {
        await outbox.fail(item.id, '$e');
        failed++;
      }
    }

    return (sent: sent, failed: failed);
  }

  Future<void> _pushOne(OutboxRow item) async {
    final target = OutboxTarget.values.byName(item.operation);

    switch (target) {
      case OutboxTarget.entry:
        // Read the row now rather than trusting a payload captured at queue
        // time: the entry may have been edited several times since.
        final entry = await _loadEntry(item.targetId);
        if (entry == null) return;

        final stored = entry.isDeleted
            ? await api.deleteEntry(entry.id)
            : await api.upsertEntry(entry);

        // Adopt the server's timestamp so the next pull does not treat our own
        // write as a change to apply.
        await _stampUpdatedAt(stored.id, stored.updatedAt);

      case OutboxTarget.group:
        final row = await (db.select(
          db.groups,
        )..where((t) => t.id.equals(item.targetId))).getSingleOrNull();
        if (row == null) return;
        final storedGroup = await api.pushGroup(row.toDomain());
        // Adopt the server's version, exactly as the entry path does. Leaving
        // a device clock here would make the next pull compare a local clock
        // against a server one, which is the comparison this column exists to
        // avoid.
        if (storedGroup.updatedAt != null) {
          await (db.update(db.groups)..where((t) => t.id.equals(row.id))).write(
            GroupsCompanion(updatedAt: Value(storedGroup.updatedAt!)),
          );
        }

      case OutboxTarget.member:
        final row = await (db.select(
          db.members,
        )..where((t) => t.id.equals(item.targetId))).getSingleOrNull();
        if (row == null) return;
        final storedMember = await api.pushMember(row.toDomain());
        if (storedMember.updatedAt != null) {
          await (db.update(
            db.members,
          )..where((t) => t.id.equals(row.id))).write(
            MembersCompanion(updatedAt: Value(storedMember.updatedAt!)),
          );
        }
    }
  }

  /// Applies every change made since the stored cursor.
  Future<int> pull(String groupId) async {
    await _pullGroupAndMembers(groupId);

    var cursor = await _readCursor(groupId);
    var applied = 0;

    while (true) {
      final page = await api.pullEntries(
        groupId: groupId,
        cursor: cursor,
        limit: pageSize,
      );

      for (final entry in page.entries) {
        if (await _applyRemote(entry)) applied++;
      }

      if (page.nextCursor != null) {
        cursor = page.nextCursor;
        await _writeCursor(groupId, cursor!);
      }
      if (!page.hasMore) break;
      // A page that reports more but advances nothing would spin forever.
      if (page.entries.isEmpty) break;
    }

    return applied;
  }

  /// Applies the group row and its members, newest write winning.
  ///
  /// These are refetched whole rather than paged by cursor — a group has one
  /// row and a handful of members, so a delta feed would cost more than it
  /// saves. What they are NOT is applied unconditionally: before these tables
  /// had an `updated_at`, this method overwrote whatever the device held on
  /// every sync, so a rename made offline was silently discarded by the next
  /// pull that happened to run before the outbox drained.
  Future<void> _pullGroupAndMembers(String groupId) async {
    final group = await api.pullGroup(groupId);
    final localGroup = await (db.select(
      db.groups,
    )..where((t) => t.id.equals(groupId))).getSingleOrNull();
    if (group != null && _remoteWins(localGroup?.updatedAt, group.updatedAt)) {
      await db
          .into(db.groups)
          .insertOnConflictUpdate(
            GroupsCompanion.insert(
              id: group.id,
              name: group.name,
              defaultCurrency: group.defaultCurrency,
              isDirect: Value(group.isDirect),
              simplifyDebts: Value(group.simplifyDebts),
              createdBy: group.createdBy,
              createdAt: group.createdAt,
              archivedAt: Value(group.archivedAt),
              updatedAt: Value(group.updatedAt ?? _clock()),
            ),
          );
    }

    // Members must land before entries: an entry's payers and shares reference
    // them, and the foreign keys are real.
    for (final member in await api.pullMembers(groupId)) {
      final localMember = await (db.select(
        db.members,
      )..where((t) => t.id.equals(member.id))).getSingleOrNull();
      if (!_remoteWins(localMember?.updatedAt, member.updatedAt)) continue;
      await db
          .into(db.members)
          .insertOnConflictUpdate(
            MembersCompanion.insert(
              id: member.id,
              groupId: member.groupId,
              profileId: Value(member.profileId),
              displayName: member.displayName,
              role: member.role,
              joinedAt: member.joinedAt,
              leftAt: Value(member.leftAt),
              upiVpa: Value(member.upiVpa),
              updatedAt: Value(member.updatedAt ?? _clock()),
            ),
          );
    }
  }

  /// Whether a remote row should replace the local one.
  ///
  /// Both sides are server timestamps once a row has been pushed, so this is a
  /// genuine last-write-wins rather than a race between two devices' clocks.
  /// A local row with no timestamp has never reached the server and cannot be
  /// the newer of the two; a remote row with none came from a backend that
  /// predates versioning, and applying it matches the old behaviour.
  static bool _remoteWins(DateTime? local, DateTime? remote) {
    if (local == null || remote == null) return true;
    return local.isBefore(remote);
  }

  /// Writes a remote entry unless the local copy is already at least as new.
  ///
  /// Both sides of this comparison are server timestamps, so it is a genuine
  /// last-write-wins and not a race between two devices' clocks.
  Future<bool> _applyRemote(Entry remote) async {
    final local = await (db.select(
      db.entries,
    )..where((t) => t.id.equals(remote.id))).getSingleOrNull();

    if (local != null && !local.updatedAt.isBefore(remote.updatedAt)) {
      return false;
    }

    await writeEntryLocally(db, remote);
    return true;
  }

  Future<Entry?> _loadEntry(String entryId) async {
    final row = await (db.select(
      db.entries,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) return null;

    final payers = await (db.select(
      db.entryPayers,
    )..where((t) => t.entryId.equals(entryId))).get();
    final shares = await (db.select(
      db.entryShares,
    )..where((t) => t.entryId.equals(entryId))).get();

    return row.toDomain(payers: payers, shares: shares);
  }

  Future<void> _stampUpdatedAt(String entryId, DateTime updatedAt) async {
    await (db.update(db.entries)..where((t) => t.id.equals(entryId))).write(
      EntriesCompanion(updatedAt: Value(updatedAt)),
    );
  }

  Future<SyncCursor?> _readCursor(String groupId) async {
    final row = await (db.select(
      db.syncCursors,
    )..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
    if (row?.cursor == null || row?.cursorId == null) return null;
    return SyncCursor(row!.cursor!, row.cursorId!);
  }

  Future<void> _writeCursor(String groupId, SyncCursor cursor) async {
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            groupId: groupId,
            cursor: Value(cursor.updatedAt),
            cursorId: Value(cursor.id),
            lastSyncedAt: Value(_clock()),
          ),
        );
  }
}
