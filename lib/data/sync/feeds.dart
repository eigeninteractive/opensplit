import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import 'change_feed.dart';
import 'outbox_queue.dart';
import 'remote_ledger_api.dart';
import 'sync_cursor.dart';
import 'wire.dart' show memberAmountsToJson;

/// Whether a remote row should replace the local one.
///
/// Both sides are server timestamps once a row has been pushed, so this is a
/// genuine last-write-wins rather than a race between two devices' clocks.
///
/// Needed even with a cursor, and the reason is worth keeping: a pull is
/// allowed to arrive after a local edit the outbox has not managed to push. The
/// cursor only says "the server changed this since you last looked" — it knows
/// nothing about what this device did in the meantime. Without this guard, a
/// rename made offline was silently discarded by the next pull that ran before
/// the outbox drained.
///
/// A local row with no timestamp has never reached the server and cannot be the
/// newer of the two; a remote row with none came from a backend that predates
/// versioning, and applying it matches the old behaviour.
bool remoteWins(DateTime? local, DateTime? remote) {
  if (local == null || remote == null) return true;
  return local.isBefore(remote);
}

/// Dirty rows are protected by intent, never by comparing device clocks.
Future<Set<String>> _dirtyIds(AppDatabase db, OutboxTarget target) async {
  final rows = await (db.select(
    db.outbox,
  )..where((t) => t.operation.equals(target.name))).get();
  return {for (final row in rows) row.targetId};
}

/// One group's own row.
///
/// A page of at most one row. See [RemoteLedgerApi.pullGroup] for why that
/// still belongs behind the same cursor as everything else.
class GroupFeed implements ChangeFeed<Group> {
  const GroupFeed(this._api, this._db, this.groupId);

  final RemoteLedgerApi _api;
  final AppDatabase _db;
  final String groupId;

  @override
  String get key => 'group:$groupId';

  @override
  Future<ChangePage<Group>> fetch({SyncCursor? since, required int limit}) =>
      _api.pullGroup(groupId: groupId, since: since, limit: limit);

  @override
  Future<int> applyInTransaction(List<Group> rows) async {
    final dirty = await _dirtyIds(_db, OutboxTarget.group);
    var applied = 0;
    for (final group in rows) {
      if (dirty.contains(group.id)) continue;
      final local = await (_db.select(
        _db.groups,
      )..where((t) => t.id.equals(group.id))).getSingleOrNull();
      if (!remoteWins(local?.updatedAt, group.updatedAt)) continue;

      await _db
          .into(_db.groups)
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
              // The server column is `not null`; the domain model is
              // nullable for a backend that predates versioning. Falling
              // back to what is already held rather than to a local clock,
              // so a row's version never moves backwards and starts being
              // rewritten on every sync.
              updatedAt: Value(
                group.updatedAt ?? local?.updatedAt ?? group.createdAt,
              ),
            ),
          );
      applied++;
    }
    return applied;
  }
}

/// One group's members, including those who have left.
///
/// Members land before entries because an entry's payers and shares reference
/// them and the local foreign keys are real.
class MemberFeed implements ChangeFeed<Member> {
  MemberFeed(this._api, this._db, this.groupId);

  final RemoteLedgerApi _api;
  final AppDatabase _db;
  final String groupId;

  /// Profiles referenced by member rows this run actually accepted.
  ///
  /// Kept on the feed so [SyncEngine] can hydrate them after the member
  /// transaction commits. A network request must never be held inside that
  /// transaction.
  final Set<String> profileIdsToHydrate = {};

  @override
  String get key => 'members:$groupId';

  @override
  Future<ChangePage<Member>> fetch({SyncCursor? since, required int limit}) =>
      _api.pullMembers(groupId: groupId, since: since, limit: limit);

  @override
  Future<int> applyInTransaction(List<Member> rows) async {
    final dirty = await _dirtyIds(_db, OutboxTarget.member);
    // The local copies in one query rather than one per row. This used to be a
    // SELECT per member inside the loop, which a group of twenty paid on every
    // sync — and there are far more syncs now that writes trigger them.
    final ids = [for (final member in rows) member.id];
    final locals = await (_db.select(
      _db.members,
    )..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final local in locals) local.id: local};

    final winners = [
      for (final member in rows)
        if (!dirty.contains(member.id) &&
            remoteWins(byId[member.id]?.updatedAt, member.updatedAt))
          member,
    ];
    if (winners.isEmpty) return 0;

    profileIdsToHydrate.addAll(
      winners.map((member) => member.profileId).nonNulls,
    );

    await _db.batch((batch) {
      for (final member in winners) {
        final row = MembersCompanion.insert(
          id: member.id,
          groupId: member.groupId,
          profileId: Value(member.profileId),
          displayName: member.displayName,
          joinedAt: member.joinedAt,
          leftAt: Value(member.leftAt),
          upiVpa: Value(member.upiVpa),
          updatedAt: Value(
            member.updatedAt ?? byId[member.id]?.updatedAt ?? member.joinedAt,
          ),
        );
        // DO UPDATE, never REPLACE. SQLite implements REPLACE as a delete
        // followed by an insert, and entry_payers.member_id references this
        // table with no cascade — so replacing a member would either fail the
        // foreign key or take an expense's shares with it.
        batch.insert(_db.members, row, onConflict: DoUpdate((_) => row));
      }
    });
    return winners.length;
  }
}

/// One group's expenses, with their payers and shares.
class EntryFeed implements ChangeFeed<Entry> {
  const EntryFeed(this._api, this._db, this.groupId);

  final RemoteLedgerApi _api;
  final AppDatabase _db;
  final String groupId;

  @override
  String get key => 'entries:$groupId';

  @override
  Future<ChangePage<Entry>> fetch({SyncCursor? since, required int limit}) =>
      _api.pullEntries(groupId: groupId, since: since, limit: limit);

  @override
  Future<int> applyInTransaction(List<Entry> rows) async {
    var applied = 0;
    final dirty = await _dirtyIds(_db, OutboxTarget.entry);
    for (final remote in rows) {
      if (dirty.contains(remote.id)) continue;
      final local = await (_db.select(
        _db.entries,
      )..where((t) => t.id.equals(remote.id))).getSingleOrNull();
      if (local != null && !local.updatedAt.isBefore(remote.updatedAt)) {
        continue;
      }
      await writeEntryInTransaction(_db, remote);

      // This row is now derived from exactly what the server holds, so the
      // base moves with it. A local edit will change `updated_at` to a
      // device clock and leave this alone, which is the pair that lets the
      // next push say what version it was composed against.
      await (_db.update(_db.entries)..where((t) => t.id.equals(remote.id)))
          .write(EntriesCompanion(baseUpdatedAt: Value(remote.updatedAt)));
      applied++;
    }
    return applied;
  }
}

/// One group's activity: what each expense looked like after each change.
class SnapshotFeed implements ChangeFeed<EntrySnapshot> {
  const SnapshotFeed(this._api, this._db, this.groupId);

  final RemoteLedgerApi _api;
  final AppDatabase _db;
  final String groupId;

  /// Its own cursor row, rather than `max(created_at)` over the local table.
  /// That table also holds this device's provisional snapshots, stamped with a
  /// device clock — often a little ahead of the server's — so asking for
  /// everything after the newest local row would skip whatever a co-member
  /// recorded in between, permanently.
  @override
  String get key => 'snapshots:$groupId';

  @override
  Future<ChangePage<EntrySnapshot>> fetch({
    SyncCursor? since,
    required int limit,
  }) => _api.pullEntrySnapshots(groupId: groupId, since: since, limit: limit);

  @override
  Future<int> applyInTransaction(List<EntrySnapshot> rows) async {
    await _db.batch((batch) {
      for (final snapshot in rows) {
        batch.insert(
          _db.entrySnapshots,
          EntrySnapshotsCompanion.insert(
            id: snapshot.id,
            entryId: snapshot.entryId,
            groupId: snapshot.groupId,
            actorId: Value(snapshot.actorId),
            createdAt: snapshot.createdAt,
            description: snapshot.description,
            currency: snapshot.currency,
            amountMinor: snapshot.amountMinor,
            entryDate: snapshot.entryDate,
            splitKind: snapshot.splitKind,
            categoryId: Value(snapshot.categoryId),
            notes: Value(snapshot.notes),
            deletedAt: Value(snapshot.deletedAt),
            payers: jsonEncode(memberAmountsToJson(snapshot.payers)),
            shares: jsonEncode(memberAmountsToJson(snapshot.shares)),
          ),
          // A snapshot is never revised, so a row already here is the same
          // row arriving twice.
          mode: InsertMode.insertOrIgnore,
        );
      }
    });

    // The server's account of these expenses has arrived, so this device's
    // guesses about them are spent.
    //
    // Superseded rather than merged, and per entry rather than per row: five
    // edits made offline are five provisional lines here and one snapshot on
    // the server, which deduped them. Keeping ours alongside would show the
    // same edit twice, in two voices, one of which nobody else can see.
    //
    // Scoped to the entries actually pulled, so a provisional line for an
    // expense whose push was refused outright stays exactly where it is --
    // which is the one case where it is the only record there is.
    final touched = {for (final snapshot in rows) snapshot.entryId};
    touched.removeAll(await _dirtyIds(_db, OutboxTarget.entry));
    await (_db.delete(
      _db.entrySnapshots,
    )..where((t) => t.entryId.isIn(touched) & t.isProvisional)).go();
    return rows.length;
  }
}

/// The name and payment handle of everybody you share a group with.
///
/// Account-wide, so it is drained once per sync rather than once per group.
class ProfileFeed implements ChangeFeed<Profile> {
  const ProfileFeed(this._api, this._db);

  final RemoteLedgerApi _api;
  final AppDatabase _db;

  /// Not group-scoped, but the cursor table is keyed by a single string, so it
  /// simply takes a name no group id can collide with.
  @override
  String get key => 'profiles';

  @override
  Future<ChangePage<Profile>> fetch({SyncCursor? since, required int limit}) =>
      _api.pullProfiles(since: since, limit: limit);

  @override
  Future<int> applyInTransaction(List<Profile> rows) async {
    final dirty = await _dirtyIds(_db, OutboxTarget.profile);
    final ids = [for (final profile in rows) profile.id];
    final locals = await (_db.select(
      _db.profiles,
    )..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final local in locals) local.id: local};

    // Guarded the same way groups and members are. Your own name is editable
    // offline, so a pull that ran before the outbox drained could otherwise
    // hand back the name you had just changed.
    final winners = [
      for (final profile in rows)
        if (!dirty.contains(profile.id) &&
            remoteWins(byId[profile.id]?.updatedAt, profile.updatedAt))
          profile,
    ];
    if (winners.isEmpty) return 0;

    await _db.batch((batch) {
      for (final profile in winners) {
        final row = ProfilesCompanion.insert(
          id: profile.id,
          displayName: Value(profile.displayName),
          avatarUrl: Value(profile.avatarUrl),
          upiVpa: Value(profile.upiVpa),
          updatedAt: Value(profile.updatedAt ?? byId[profile.id]?.updatedAt),
        );
        batch.insert(_db.profiles, row, onConflict: DoUpdate((_) => row));
      }
    });
    return winners.length;
  }
}
