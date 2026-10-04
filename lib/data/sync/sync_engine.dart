import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart' as dio;
import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import '../local/tables.dart';
import 'api_client.dart';
import 'apply_changes.dart';
import 'outbox_queue.dart';
import 'shared_feeds.dart';
import 'sync_gate.dart';
import 'sync_session.dart';
import 'wire.dart';

/// What one sync run did.
class SyncReport {
  const SyncReport({
    required this.pushed,
    required this.pulled,
    required this.failed,
    this.error,
    this.stackTrace,
    this.nextPushAt,
  });

  final int pushed;
  final int pulled;
  final int failed;
  final Object? error;
  final StackTrace? stackTrace;

  /// The earliest pending write's next attempt, excluding dead letters.
  final DateTime? nextPushAt;

  bool get isClean => failed == 0 && error == null && nextPushAt == null;

  SyncReport withNextPushAt(DateTime? at) => SyncReport(
    pushed: pushed,
    pulled: pulled,
    failed: failed,
    error: error,
    stackTrace: stackTrace,
    nextPushAt: at,
  );

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, pulled: $pulled, failed: $failed'
      '${error == null ? '' : ', error: $error'})';
}

/// Moves rows between this device and the server: push the outbox, then pull
/// each group's changes after its cursor, so the pull brings back the server's
/// version of what was just sent.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.client,
    required this.outbox,
    this.accountId,
    SyncGate? gate,
    DateTime Function()? clock,
    this.pageSize = 200,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now,
       _gate = gate ?? createSyncGate(db) {
    shared = SharedFeeds(
      db: db,
      client: client,
      clock: _clock,
      requestTimeout: requestTimeout,
      pageSize: pageSize,
      assertActive: _assertActive,
    );
  }

  final AppDatabase db;
  final api.OpensplitApi client;
  final OutboxQueue outbox;

  /// The account this ledger belongs to, which is how a group it has left is
  /// recognised. Null only where there is no account to ask about.
  final String? accountId;
  final DateTime Function() _clock;
  final SyncGate _gate;
  final int pageSize;
  final Duration requestTimeout;

  /// Reference data, rates and profiles.
  late final SharedFeeds shared;

  Future<void> _tail = Future<void>.value();
  String? _activeEpoch;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _gate.dispose();
  }

  Future<void> _assertActive() async {
    final session = await readSyncSession(db);
    if (_disposed ||
        !session.enabled ||
        (_activeEpoch != null && session.epoch != _activeEpoch)) {
      throw StateError('This account synchronization has ended.');
    }
    if (_activeEpoch != null) await _gate.assertHeld();
  }

  Future<T> _call<T>(Future<dio.Response<T>> request) =>
      fetch(request).timeout(requestTimeout);

  /// The groups this account is in, by the server's account and this
  /// device's, less those [_unreadable] says not to ask about. Throws when the
  /// server cannot be asked: the local list alone cannot show that an account
  /// has no other groups.
  Future<List<String>> discoverGroups() async {
    final answer = await _call(
      client.getSyncApi().pull(
        pullRequest: api.PullRequest(groups: const [], limit: pageSize),
      ),
    );
    final skipped = await _unreadable();
    return {
      for (final row in await db.select(db.groups).get()) row.id,
      ...answer.groupIds,
    }.difference(skipped).toList()..sort();
  }

  /// Groups a pull can only waste a request on: ones the server has never
  /// acknowledged (their creation is still in the outbox, and the server
  /// would answer `no_group`), and ones this account has left for good.
  Future<Set<String>> _unreadable() async => {
    for (final group in await (db.select(
      db.groups,
    )..where((t) => t.seq.isNull())).get())
      group.id,
    ...await _leftForGood(),
  };

  /// Groups this account has left or been removed from, and this device has
  /// already read that back from the server. A pull of one can only ever come
  /// back empty. An invite link brings the group back, and the server then
  /// names it among the account's groups again.
  Future<Set<String>> _leftForGood() async {
    final account = accountId;
    if (account == null) return const {};

    final departed =
        await (db.select(db.members)..where(
              (t) =>
                  t.profileId.equals(account) &
                  t.leftAt.isNotNull() &
                  t.seq.isNotNull(),
            ))
            .get();
    if (departed.isEmpty) return const {};

    final cursors = await _groupCursors();
    // Unsent, the leave is this device's word alone, and the server may still
    // refuse it.
    final unsent = await outbox.unsentIds(OutboxTarget.member);
    return {
      for (final member in departed)
        if (!unsent.contains(member.id) &&
            (cursors[member.groupId] ?? 0) >= member.seq!)
          member.groupId,
    };
  }

  /// Pushes what is waiting, then reads [groupIds] and every group the push
  /// wrote to. What a screen, a local write or a push message asks for: the
  /// shared feeds are left to [syncEverything].
  Future<SyncReport> syncGroups(Set<String> groupIds) =>
      _serialized(() => _run(groupIds: groupIds));

  Future<SyncReport> syncGroup(String groupId) => syncGroups({groupId});

  /// The outbox, the shared feeds, and every group the account is in.
  Future<SyncReport> syncEverything() =>
      _serialized(() => _run(groupIds: const {}, everything: true));

  Future<SyncReport> _run({
    required Set<String> groupIds,
    bool everything = false,
  }) async {
    final pushed = await push();
    try {
      if (everything) {
        await shared.pullAll();
      } else {
        await shared.pullFxRates();
      }
      final pulled = await _pull({
        ...groupIds,
        ...pushed.groups,
      }, everything: everything);
      return SyncReport(
        pushed: pushed.sent,
        pulled: pulled,
        failed: pushed.failed,
      );
    } catch (error, stackTrace) {
      return SyncReport(
        pushed: pushed.sent,
        pulled: 0,
        failed: pushed.failed,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Queues runs in this isolate and holds the platform's sync gate, which
  /// covers a background isolate or another browser tab.
  Future<SyncReport> _serialized(Future<SyncReport> Function() operation) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;

    return () async {
      await previous;
      try {
        if (_disposed) throw StateError('This sync engine is disposed.');
        return await _gate.synchronized(() async {
          _activeEpoch = (await readSyncSession(db)).epoch;
          await _assertActive();
          // Another isolate may have held the gate, and written, just now.
          await db.noticeWritesElsewhere();
          final report = await operation();
          return report.withNextPushAt(await outbox.nextAttemptAt());
        });
      } catch (error, stackTrace) {
        return SyncReport(
          pushed: 0,
          pulled: 0,
          failed: 0,
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _activeEpoch = null;
        released.complete();
      }
    }();
  }

  /// A backstop on [push]: each item is completed, backed off or
  /// dead-lettered, so the loop ends unless the queue refills as it drains.
  static const int _maxPushRounds = 50;

  /// Sends the outbox in order. [groups] are the ones it wrote to, or found
  /// it needs to read back.
  Future<({int sent, int failed, Set<String> groups})> push() async {
    var sent = 0;
    var failed = 0;
    final groups = <String>{};

    for (var round = 0; round < _maxPushRounds; round++) {
      await _assertActive();
      final due = await outbox.due();
      if (due.isEmpty) break;

      for (final item in due) {
        try {
          if (await _pushOne(item) case final groupId?) groups.add(groupId);
          await outbox.complete(item);
          sent++;
        } on ApiFailure catch (e) {
          switch (e.retry) {
            case api.Retry.stale:
              if (await _parkConflict(item) case final groupId?) {
                groups.add(groupId);
              }
            case api.Retry.transient:
              await outbox.fail(item, e.message);
              return (sent: sent, failed: failed + 1, groups: groups);
            // Refused identically next time; retrying would wedge the queue.
            case api.Retry.permanent:
            case api.Retry.unknownDefaultOpenApi:
              await outbox.fail(item, e.message, permanent: true);
          }
          failed++;
        } catch (e) {
          // A connection failure affects the whole batch.
          await outbox.fail(item, '$e');
          return (sent: sent, failed: failed + 1, groups: groups);
        }
      }
    }
    return (sent: sent, failed: failed, groups: groups);
  }

  /// Parks an edit the server refused as stale for a person to read, and
  /// rewinds the cursor to its base so the next pull brings the server's
  /// version (skipped while the row was dirty). Answers the group to read.
  Future<String?> _parkConflict(OutboxRow item) async {
    return db.transaction(() async {
      if (!await outbox.isCurrent(item)) return null;
      final entry = await _loadEntry(item.targetId);
      if (entry == null) return null;

      await db
          .into(db.entryConflicts)
          .insertOnConflictUpdate(
            EntryConflictsCompanion.insert(
              entryId: entry.id,
              groupId: entry.row.groupId,
              attempted: snapshotOf(entry),
              baseSeq: Value(entry.row.seq),
              rejectedAt: _clock(),
            ),
          );
      await _rewindCursor(entry.row.groupId, to: entry.row.seq ?? 0);
      await outbox.complete(item);
      return entry.row.groupId;
    });
  }

  /// Drops every write the server refused outright. A row the server has is
  /// re-read from before this device's copy; one it never had is deleted,
  /// except a member an expense still names.
  Future<SyncReport> discardRefused() => _serialized(() async {
    final refused = await outbox.deadLetters();
    // Expenses before the members they name, members before their group.
    refused.sort((a, b) => b.target.index.compareTo(a.target.index));
    await db.transaction(() async {
      for (final item in refused) {
        await _discard(item.target, item.targetId);
        await outbox.complete(item);
      }
    });
    return const SyncReport(pushed: 0, pulled: 0, failed: 0);
  });

  Future<void> _discard(OutboxTarget target, String id) async {
    switch (target) {
      case OutboxTarget.entry:
        final row = await (db.select(
          db.entries,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        await _dropProvisionalLines(row.groupId, subjectId: id);
        if (row.seq case final seq?) {
          return _rewindCursor(row.groupId, to: seq - 1);
        }
        await (db.delete(db.entries)..where((t) => t.id.equals(id))).go();
      case OutboxTarget.member:
        final row = await (db.select(
          db.members,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        await _dropProvisionalLines(row.groupId, subjectId: id);
        if (row.seq case final seq?) {
          return _rewindCursor(row.groupId, to: seq - 1);
        }
        if (await _isNamedByAnExpense(id)) return;
        await (db.delete(db.members)..where((t) => t.id.equals(id))).go();
      case OutboxTarget.group:
        final row = await (db.select(
          db.groups,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        await _dropProvisionalLines(id, subjectId: null);
        if (row.seq case final seq?) return _rewindCursor(id, to: seq - 1);
        await (db.delete(db.groups)..where((t) => t.id.equals(id))).go();
      case OutboxTarget.profile:
        // Not on a group's feed: forget this copy's version and re-read.
        await (db.update(db.profiles)..where((t) => t.id.equals(id))).write(
          const ProfilesCompanion(version: Value(null)),
        );
        await shared.resetProfileFeed();
    }
  }

  Future<void> _dropProvisionalLines(
    String groupId, {
    required String? subjectId,
  }) =>
      (db.delete(db.groupEvents)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.isProvisional &
                (subjectId == null
                    ? t.subjectId.isNull()
                    : t.subjectId.equals(subjectId)),
          ))
          .go();

  Future<bool> _isNamedByAnExpense(String memberId) async {
    final payer =
        await (db.select(db.entryPayers)
              ..where((t) => t.memberId.equals(memberId))
              ..limit(1))
            .getSingleOrNull();
    if (payer != null) return true;
    final share =
        await (db.select(db.entryShares)
              ..where((t) => t.memberId.equals(memberId))
              ..limit(1))
            .getSingleOrNull();
    return share != null;
  }

  Future<void> _rewindCursor(String groupId, {required int to}) =>
      (db.update(db.groupCursors)..where(
            (t) => t.groupId.equals(groupId) & t.seq.isBiggerThanValue(to),
          ))
          .write(GroupCursorsCompanion(seq: Value(to)));

  /// Sends one dirty row, read now rather than at queue time, and records the
  /// sequence number the server gave it: its version and the next edit's base.
  /// Answers the group it wrote to, if it sent anything that has one.
  Future<String?> _pushOne(OutboxRow item) async {
    switch (item.target) {
      case OutboxTarget.entry:
        final entry = await _snapshot(item, () => _loadEntry(item.targetId));
        if (entry == null) return null;
        // Created and deleted before its first push: nothing remote to delete.
        if (entry.isDeleted && entry.row.seq == null) return null;

        final stored = await _call(
          client.getEntriesApi().putEntry(
            groupId: entry.row.groupId,
            entryId: entry.id,
            entryInput: entry.toInput(),
          ),
        );
        await db.transaction(() async {
          await _assertActive();
          await (db.update(db.entries)..where((t) => t.id.equals(stored.id)))
              .write(EntriesCompanion(seq: Value(stored.seq)));
        });
        return entry.row.groupId;

      case OutboxTarget.group:
        final group = await _snapshot(
          item,
          () => (db.select(
            db.groups,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (group == null) return null;

        // A group the server has never seen is created with its creator.
        final creator = await _creatorOf(group);
        final stored = await _call(
          client.getGroupsApi().putGroup(
            groupId: group.id,
            groupInput: group.toInput(creator),
          ),
        );
        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.groups)..where((t) => t.id.equals(group.id)))
              .write(GroupsCompanion(seq: Value(stored.seq)));
          // The creator landed in the same change; this stops a second push.
          if (group.seq == null) {
            await (db.update(db.members)..where((t) => t.id.equals(creator.id)))
                .write(MembersCompanion(seq: Value(stored.seq)));
          }
        });
        return group.id;

      case OutboxTarget.member:
        final member = await _snapshot(
          item,
          () => (db.select(
            db.members,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (member == null) return null;

        final stored = await _call(
          client.getGroupsApi().putMember(
            groupId: member.groupId,
            memberId: member.id,
            memberInput: member.toInput(),
          ),
        );
        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.members)..where((t) => t.id.equals(member.id)))
              .write(MembersCompanion(seq: Value(stored.seq)));
        });
        return member.groupId;

      case OutboxTarget.profile:
        final profile = await _snapshot(
          item,
          () => (db.select(
            db.profiles,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (profile == null) return null;

        final stored = await _call(
          client.getSyncApi().updateProfile(profileUpdate: profile.toUpdate()),
        );
        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.profiles)..where((t) => t.id.equals(profile.id)))
              .write(ProfilesCompanion(version: Value(stored.version)));
        });
        return null;
    }
  }

  Future<Member> _creatorOf(Group group) async {
    final creatorId = group.createdBy;
    final creator = creatorId == null
        ? null
        : await (db.select(
            db.members,
          )..where((t) => t.id.equals(creatorId))).getSingleOrNull();
    if (creator == null) {
      throw const ApiFailure(
        'A group cannot be created without its first member.',
        retry: api.Retry.permanent,
      );
    }
    return creator;
  }

  /// One group's changes after its cursor, page by page.
  Future<int> pull(String groupId) => _pull({groupId}, everything: false);

  /// The most groups the server reads in one pull.
  static const _groupsPerPull = 50;

  /// Reads [groupIds] past their cursors, many groups to a request, until each
  /// is caught up or refused. With [everything], also every group this
  /// account is in, and the server's answer names any it joined elsewhere.
  ///
  /// A group the server refuses is logged and left as it is here: one group
  /// it cannot read says nothing about the others.
  Future<int> _pull(Set<String> groupIds, {required bool everything}) async {
    final cursors = await _groupCursors();
    final skipped = await _unreadable();
    final wanted = <String, int>{};
    final done = <String>{};
    void want(String groupId) {
      if (done.contains(groupId) || skipped.contains(groupId)) return;
      wanted.putIfAbsent(groupId, () => cursors[groupId] ?? 0);
    }

    if (everything) {
      for (final group in await db.select(db.groups).get()) {
        want(group.id);
      }
    }
    groupIds.forEach(want);

    var applied = 0;
    var asked = false;
    while (wanted.isNotEmpty || (everything && !asked)) {
      await _assertActive();
      final batch = [
        for (final MapEntry(key: groupId, value: since) in wanted.entries.take(
          _groupsPerPull,
        ))
          api.GroupCursor(groupId: groupId, since: since),
      ];
      final answer = await _call(
        client.getSyncApi().pull(
          pullRequest: api.PullRequest(groups: batch, limit: pageSize),
        ),
      );
      asked = true;

      for (final cursor in batch) {
        wanted.remove(cursor.groupId);
        done.add(cursor.groupId);
      }
      for (final page in answer.pages) {
        applied += await applyGroupChanges(db, page, now: _clock());
        final since = cursors[page.groupId] ?? 0;
        cursors[page.groupId] = page.seq;
        if (page.hasMore && page.purgedAt == null && page.seq > since) {
          done.remove(page.groupId);
          want(page.groupId);
        }
      }
      for (final refusal in answer.refusals) {
        developer.log(
          'Group ${refusal.groupId} was not read: ${refusal.message}',
          name: 'opensplit.sync',
          level: 900,
        );
      }
      if (everything) answer.groupIds.forEach(want);
    }
    return applied;
  }

  Future<Map<String, int>> _groupCursors() async => {
    for (final cursor in await db.select(db.groupCursors).get())
      cursor.groupId: cursor.seq,
  };

  Future<Entry?> _loadEntry(String entryId) async {
    final row = await (db.select(
      db.entries,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) return null;

    return entryFromRows(
      row,
      payers: await (db.select(
        db.entryPayers,
      )..where((t) => t.entryId.equals(entryId))).get(),
      shares: await (db.select(
        db.entryShares,
      )..where((t) => t.entryId.equals(entryId))).get(),
    );
  }

  /// Reads a row for pushing, unless a newer edit has replaced [item].
  Future<T?> _snapshot<T>(OutboxRow item, Future<T?> Function() read) =>
      db.transaction(() async {
        await _assertActive();
        if (!await outbox.isCurrent(item)) return null;
        return read();
      });
}
