import 'dart:convert';
import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/entry_event.dart';
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

  /// Every group the server says this account belongs to, including ones this
  /// device has never seen.
  ///
  /// The local group list is not the answer to "what should I sync?" — it is
  /// the answer to "what have I synced already", and on a second device or
  /// after a reinstall those are very different. Local ids are folded in so a
  /// group created offline, which the server does not know about yet, is not
  /// dropped from the sweep on its way to being pushed.
  ///
  /// Failure falls back to what is local. Being offline must not empty the
  /// list and skip pushing the very rows that are waiting to go out.
  Future<List<String>> discoverGroups() async {
    final local = await db.select(db.groups).get();
    final ids = <String>{for (final row in local) row.id};

    try {
      ids.addAll(await api.pullMyGroupIds());
    } catch (_) {
      // Offline, or the account has no session yet. Local is a safe answer.
    }
    return ids.toList()..sort();
  }

  Future<SyncReport> syncGroup(String groupId) async {
    final pushed = await push();
    try {
      await pullShared();
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

  /// Syncs every group this account belongs to, in one run.
  ///
  /// Here rather than in the caller because the saving is only available here:
  /// the outbox is drained once for the whole sweep, and rates and profiles —
  /// which are not group-scoped at all — are pulled once rather than once per
  /// group. Driven from outside, this was N pushes and 2N requests for
  /// reference data to sync N groups.
  ///
  /// One report for the run, not the last group's. Failures pushing are counted
  /// once; a group that cannot be pulled ends the sweep, since the likely cause
  /// is the connection rather than that group.
  Future<SyncReport> syncEverything() async {
    final pushed = await push();
    var pulled = 0;
    try {
      await pullShared();
      for (final groupId in await discoverGroups()) {
        pulled += await pull(groupId);
      }
      return SyncReport(
        pushed: pushed.sent,
        pulled: pulled,
        failed: pushed.failed,
      );
    } catch (error) {
      return SyncReport(
        pushed: pushed.sent,
        pulled: pulled,
        failed: pushed.failed,
        error: error,
      );
    }
  }

  /// Everything a pull needs that is not about one group.
  ///
  /// Exchange rates and profiles are app-wide: rates are reference data, and
  /// `profiles_read` already scopes profiles to you plus your co-members, so
  /// one request answers for every group at once. Pulling them per group meant
  /// a person in three of your groups was fetched three times and the rate
  /// table was swept three times, to no effect after the first.
  Future<void> pullShared() async {
    await pullFxRates();
    await pullProfiles();
  }

  /// A backstop on [push], not the thing that ends it — see there.
  static const int _maxPushRounds = 50;

  /// Drains the outbox until nothing more is due.
  ///
  /// A page at a time, because [OutboxQueue.due] answers a bounded one — it
  /// sorts in memory, so it has to. A single pass therefore drained at most
  /// that many rows and left the rest for the next sync, and that was not
  /// merely slow: [pull] runs immediately afterwards, and a row still waiting
  /// to be pushed carries a *device* clock in `updated_at`, which is what
  /// `_applyRemote` then compares against the server's. A long offline session
  /// could have an edit overwritten by the pull that followed the push which
  /// had not reached it — silently, and without even a dead letter to show for
  /// it, since the item was never attempted.
  ///
  /// Terminating is not an assumption. Every item in a page is either
  /// completed, which deletes it, or failed, which either sets a future
  /// `nextAttemptAt` or dead-letters it — and `due` excludes both. So each
  /// round strictly shrinks what the next one can see. The round cap guards
  /// only against a queue being refilled from elsewhere as fast as it drains.
  Future<({int sent, int failed})> push() async {
    var sent = 0;
    var failed = 0;

    for (var round = 0; round < _maxPushRounds; round++) {
      final due = await outbox.due();
      if (due.isEmpty) break;

      for (final item in due) {
        try {
          await _pushOne(item);
          await outbox.complete(item.id);
          sent++;
        } on RemoteRejected catch (e) {
          // A rejected invariant or a permission failure will be rejected
          // exactly the same way next time. Retrying forever would wedge
          // everything queued behind it, so it is dropped and recorded
          // instead.
          await outbox.fail(item.id, e.message, permanent: e.permanent);
          failed++;
        } catch (e) {
          await outbox.fail(item.id, '$e');
          failed++;
        }
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

      case OutboxTarget.profile:
        // Your own name and payment handle. Only ever your own row: the server
        // policy allows an update where `id = auth.uid()` and nothing else, so
        // there is no queued write here that could touch anybody else's.
        final row = await (db.select(
          db.profiles,
        )..where((t) => t.id.equals(item.targetId))).getSingleOrNull();
        if (row == null) return;
        await api.pushProfile(row.toDomain());
    }
  }

  /// Applies every change made since the stored cursor.
  /// The name and payment handle of everybody you share a group with.
  ///
  /// Not per group: `profiles_read` on the server already scopes this to your
  /// own row plus your co-members, so one request answers for every group at
  /// once and a person in three of your groups is fetched once rather than
  /// three times.
  ///
  /// Cursored on `updated_at` like everything else, under a reserved group id
  /// — profiles are not group-scoped, but the cursor table is keyed that way
  /// and inventing a second table for one row would be worse.
  static const profilesCursorKey = '__profiles__';

  Future<void> pullProfiles() async {
    final row = await (db.select(
      db.syncCursors,
    )..where((t) => t.groupId.equals(profilesCursorKey))).getSingleOrNull();

    final profiles = await api.pullProfiles(since: row?.cursor);
    if (profiles.isEmpty) return;

    await db.batch((batch) {
      for (final profile in profiles) {
        batch.insert(
          db.profiles,
          ProfilesCompanion.insert(
            id: profile.id,
            displayName: Value(profile.displayName),
            avatarUrl: Value(profile.avatarUrl),
            upiVpa: Value(profile.upiVpa),
          ),
          onConflict: DoUpdate(
            (_) => ProfilesCompanion(
              displayName: Value(profile.displayName),
              avatarUrl: Value(profile.avatarUrl),
              upiVpa: Value(profile.upiVpa),
            ),
          ),
        );
      }
    });

    // The server orders by updated_at, so the last row carries the newest.
    // Stored as the server reported it: comparing a device clock against a
    // server one is exactly what this column exists to avoid.
    final newest = profiles.last.updatedAt;
    if (newest != null) {
      await db
          .into(db.syncCursors)
          .insertOnConflictUpdate(
            SyncCursorsCompanion.insert(
              groupId: profilesCursorKey,
              cursor: Value(newest),
              lastSyncedAt: Value(_clock()),
            ),
          );
    }
  }

  /// The group's activity feed, appended to locally and never written to.
  ///
  /// Cursored on `created_at` alone rather than the `(updated_at, id)` pair the
  /// entries feed uses, and it can be: these rows are append-only and stamped
  /// with `clock_timestamp()`, so no two share a value and none is ever
  /// revised. There is nothing for a tie-breaker to break.
  Future<void> _pullEntryEvents(String groupId) async {
    final newest =
        await (db.selectOnly(db.entryEvents)
              ..addColumns([db.entryEvents.createdAt.max()])
              ..where(db.entryEvents.groupId.equals(groupId)))
            .map((row) => row.read(db.entryEvents.createdAt.max()))
            .getSingleOrNull();

    final events = await api.pullEntryEvents(groupId: groupId, since: newest);
    if (events.isEmpty) return;

    await db.batch((batch) {
      for (final event in events) {
        batch.insert(
          db.entryEvents,
          EntryEventsCompanion.insert(
            id: event.id,
            entryId: event.entryId,
            groupId: event.groupId,
            actorId: event.actorId,
            kind: event.kind.name,
            changes: Value(
              event.changes.isEmpty ? null : jsonEncode(_encode(event.changes)),
            ),
            createdAt: event.createdAt,
          ),
          // An event never changes, so a row already here is the same row.
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Map<String, dynamic> _encode(List<FieldChange> changes) => {
    for (final change in changes)
      change.field: {'from': change.from, 'to': change.to},
  };

  /// Applies one group's changes: its row, its members, its entries and its
  /// activity.
  ///
  /// Deliberately does NOT pull rates or profiles — see [pullShared], which the
  /// callers run once per sync rather than once per group.
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

      // One transaction for the page, not one per row. Each _applyRemote
      // writes an entry and replaces its payers and shares, so a 200-row page
      // was 200 separate commits — and SQLite's cost here is dominated by the
      // commit, not the statements. Drift nests the inner transactions as
      // savepoints, so this changes the number of fsyncs, not the semantics.
      await db.transaction(() async {
        for (final entry in page.entries) {
          if (await _applyRemote(entry)) applied++;
        }
      });

      if (page.nextCursor != null) {
        cursor = page.nextCursor;
        await _writeCursor(groupId, cursor!);
      }
      if (!page.hasMore) break;
      // A page that reports more but advances nothing would spin forever.
      if (page.entries.isEmpty) break;
    }

    // Last, and it has to be. Every event references the entry it describes,
    // and foreign keys are enforced on this database — so pulling the feed
    // before the entries it talks about fails the constraint and takes the
    // whole sync down with it. On a device seeing the group for the first
    // time, that is every event there is.
    await _pullEntryEvents(groupId);

    return applied;
  }

  /// Mirrors published exchange rates onto the device.
  ///
  /// Rates are immutable once published, so this is a high-water mark rather
  /// than a cursor: ask for everything on or after the newest date held, and on
  /// a settled device that returns nothing. A device with no rates at all takes
  /// a bounded window rather than all history, because a first sync should not
  /// pull years of reference data to convert a dinner.
  ///
  /// Failure is swallowed. A missing rate costs an estimate, never a balance,
  /// and it must not be able to fail a sync that carries actual money.
  Future<int> pullFxRates() async {
    try {
      final newest = await _newestRateDate();
      final since = newest ?? _isoDay(_clock().toUtc().subtract(_rateWindow));

      final rates = await api.pullFxRates(since: since);
      if (rates.isEmpty) return 0;

      await db.batch((batch) {
        for (final rate in rates) {
          batch.insert(
            db.fxRates,
            FxRatesCompanion.insert(
              asOf: rate.asOf,
              currency: rate.currency,
              rate: rate.rate,
              source: rate.source,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
      return rates.length;
    } catch (_) {
      return 0;
    }
  }

  /// How far back a device with no rates at all reaches on its first sync.
  static const _rateWindow = Duration(days: 400);

  Future<String?> _newestRateDate() async {
    final row =
        await (db.select(db.fxRates)
              ..orderBy([(t) => OrderingTerm.desc(t.asOf)])
              ..limit(1))
            .getSingleOrNull();
    return row?.asOf;
  }

  static String _isoDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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
              createdBy: Value(group.createdBy),
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
