import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../local/database.dart';
import '../repositories/mappers.dart';
import 'change_feed.dart';
import 'feeds.dart';
import 'outbox_queue.dart';
import 'remote_ledger_api.dart';
import 'sync_cursor.dart';
import 'wire.dart' show entryToJson;

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
    await drain(ProfileFeed(api, db));
  }

  /// Runs one feed to exhaustion.
  ///
  /// The entire pull engine. Every feed is the same shape -- see [ChangeFeed] --
  /// so the parts that are easy to get wrong are written once here rather than
  /// five times with five sets of mistakes.
  ///
  /// Two orderings in six lines are load-bearing. The cursor is written *after*
  /// the page is applied, so a crash or a dropped connection re-reads a page
  /// rather than skipping it: every apply is idempotent, and re-reading costs a
  /// request while skipping costs an expense. And the cursor comes from the
  /// page, not from the rows -- an adapter reports where the feed stands, which
  /// is the only thing that knows how its own ordering works.
  ///
  /// Terminating is not an assumption either. A page that reports more but
  /// carries nothing would spin forever, so an empty page ends the loop
  /// regardless of what it claims.
  Future<int> drain<T>(ChangeFeed<T> feed) async {
    var cursor = await _readCursor(feed.key);
    var applied = 0;

    while (true) {
      final page = await feed.fetch(since: cursor, limit: pageSize);
      if (page.rows.isEmpty) break;

      applied += await feed.apply(page.rows);

      final next = page.cursor;
      if (next == null) break;
      cursor = next;
      await _writeCursor(feed.key, next);

      if (!page.hasMore) break;
    }

    return applied;
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
  /// [EntryFeed] then compares against the server's. A long offline session
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
          switch (e.kind) {
            // Composed against a version somebody has since changed. Neither a
            // retry nor a dead letter; see _parkConflict.
            case RejectionKind.stale:
              await _parkConflict(item, e);
            // A rejected invariant or a permission failure will be rejected
            // exactly the same way next time. Retrying forever would wedge
            // everything queued behind it, so it is dropped and recorded
            // instead.
            case RejectionKind.permanent:
              await outbox.fail(item.id, e.message, permanent: true);
            case RejectionKind.transient:
              await outbox.fail(item.id, e.message);
          }
          failed++;
        } catch (e) {
          await outbox.fail(item.id, '$e');
          failed++;
        }
      }
    }

    return (sent: sent, failed: failed);
  }

  /// Takes a refused edit out of the queue and parks it for a person.
  ///
  /// Three things happen, and the order of the middle one is the point.
  ///
  /// The intention is stashed whole, because it is the only copy: the local
  /// row is about to become the server's. Then the row's version marker is
  /// wound back to the base it was composed against, which is what lets the
  /// pull immediately afterwards apply the server's version over the top --
  /// without it, [EntryFeed]'s last-write-wins guard sees a local clock newer
  /// than the server's, keeps this device's rejected copy, and leaves the group
  /// permanently split over one expense. And the item leaves the queue, because
  /// resending it is refused identically forever.
  ///
  /// The ledger converges and the intention waits. The other direction --
  /// holding this device's version until somebody decides -- would leave these
  /// balances disagreeing with everybody else's for as long as nobody noticed,
  /// which is the failure this whole design exists to make impossible.
  Future<void> _parkConflict(OutboxRow item, RemoteRejected rejection) async {
    final loaded = await _loadEntry(item.targetId);
    if (loaded == null) return;
    final (entry, base) = loaded;

    await db.transaction(() async {
      await db
          .into(db.entryConflicts)
          .insertOnConflictUpdate(
            EntryConflictsCompanion.insert(
              entryId: entry.id,
              groupId: entry.groupId,
              attempted: jsonEncode(entryToJson(entry)),
              reason: rejection.message,
              rejectedAt: _clock(),
            ),
          );

      if (base != null) {
        await (db.update(db.entries)..where((t) => t.id.equals(entry.id)))
            .write(EntriesCompanion(updatedAt: Value(base)));
      }
    });

    await outbox.complete(item.id);
  }

  Future<void> _pushOne(OutboxRow item) async {
    final target = OutboxTarget.values.byName(item.operation);

    switch (target) {
      case OutboxTarget.entry:
        // Read the row now rather than trusting a payload captured at queue
        // time: the entry may have been edited several times since.
        final loaded = await _loadEntry(item.targetId);
        if (loaded == null) return;
        final (entry, base) = loaded;

        final stored = entry.isDeleted
            ? await api.deleteEntry(entry.id)
            // The base goes with it, so the server can tell an ordinary edit
            // from one composed against a version somebody has since changed.
            : await api.upsertEntry(entry, baseUpdatedAt: base);

        // Adopt the server's timestamp so the next pull does not treat our own
        // write as a change to apply -- and move the base with it, since this
        // row is now derived from exactly what the server just stored.
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

  /// Applies one group's changes: its row, its members, its entries and its
  /// activity.
  ///
  /// The order is the local foreign key graph, and it is not optional. Members
  /// reference the group; an entry's payers and shares reference members; a
  /// snapshot references the entry it describes and the member who made the
  /// change. Pulling activity before the expenses it talks about fails the
  /// constraint and takes the whole sync down with it -- which, on a device
  /// seeing the group for the first time, is every row there is.
  ///
  /// Deliberately does NOT pull rates or profiles -- see [pullShared], which the
  /// callers run once per sync rather than once per group.
  ///
  /// Counts entries only. It is the number the callers report and the only one
  /// that means "something happened to the money"; a renamed group is a change
  /// nobody needs counted.
  Future<int> pull(String groupId) async {
    await drain(GroupFeed(api, db, groupId));
    await drain(MemberFeed(api, db, groupId));
    final entries = await drain(EntryFeed(api, db, groupId));
    await drain(SnapshotFeed(api, db, groupId));
    return entries;
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

  /// The entry, and the server version it was composed against.
  Future<(Entry, DateTime?)?> _loadEntry(String entryId) async {
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

    return (row.toDomain(payers: payers, shares: shares), row.baseUpdatedAt);
  }

  Future<void> _stampUpdatedAt(String entryId, DateTime updatedAt) async {
    await (db.update(db.entries)..where((t) => t.id.equals(entryId))).write(
      EntriesCompanion(
        updatedAt: Value(updatedAt),
        baseUpdatedAt: Value(updatedAt),
      ),
    );
  }

  Future<SyncCursor?> _readCursor(String feed) async {
    final row = await (db.select(
      db.syncCursors,
    )..where((t) => t.feed.equals(feed))).getSingleOrNull();
    final at = row?.cursor;
    final id = row?.cursorId;
    if (at == null || id == null) return null;
    return SyncCursor(at, id);
  }

  Future<void> _writeCursor(String feed, SyncCursor cursor) async {
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            feed: feed,
            cursor: Value(cursor.at),
            cursorId: Value(cursor.id),
            lastSyncedAt: Value(_clock()),
          ),
        );
  }
}
