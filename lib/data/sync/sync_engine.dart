import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/calendar_date.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../local/database.dart';
import '../local/entry_writer.dart';
import 'api_client.dart';
import 'apply_changes.dart';
import 'outbox_queue.dart';
import 'remote_ledger_api.dart';
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

  /// The origin of [error], when the failing boundary preserved it.
  final StackTrace? stackTrace;

  /// The earliest pending write's next attempt, excluding dead letters.
  final DateTime? nextPushAt;

  bool get isClean => failed == 0 && error == null && nextPushAt == null;

  @override
  String toString() =>
      'SyncReport(pushed: $pushed, pulled: $pulled, failed: $failed'
      '${error == null ? '' : ', error: $error'})';
}

/// Moves rows between this device and the server: push the outbox, then pull
/// each group's changes after its cursor.
///
/// Push goes first so the pull that follows brings back the server's version
/// of what was just sent, with its sequence number.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.remote,
    required this.outbox,
    SyncGate? gate,
    DateTime Function()? clock,
    this.pageSize = 200,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now,
       _gate = gate ?? createSyncGate(db);

  final AppDatabase db;
  final RemoteLedgerApi remote;
  final OutboxQueue outbox;
  final DateTime Function() _clock;
  final SyncGate _gate;
  final int pageSize;

  /// Maximum wait per network operation before preserving the write for retry.
  final Duration requestTimeout;

  Future<void> _tail = Future<void>.value();
  String? _activeEpoch;
  bool _disposed = false;

  /// Stops queued and future runs when the account-scoped provider is disposed.
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

  /// Every group the server says this account belongs to, plus any local one
  /// the server has not seen yet (created offline, on its way to being pushed).
  ///
  /// Throws if the server cannot be asked: the local list alone cannot show
  /// that an account has no other groups.
  Future<List<String>> discoverGroups() async {
    final local = await db.select(db.groups).get();
    final bootstrap = await remote.bootstrap().timeout(requestTimeout);
    return {for (final row in local) row.id, ...bootstrap.groupIds}.toList()
      ..sort();
  }

  Future<SyncReport> syncGroup(String groupId) =>
      _serialized(() => _run(() async => pull(groupId)));

  /// Syncs every group in one run: the outbox is drained once, and rates and
  /// profiles — which are not group-scoped — are pulled once.
  ///
  /// A group that cannot be pulled ends the sweep, since the likely cause is
  /// the connection rather than that group.
  Future<SyncReport> syncEverything() => _serialized(
    () => _run(() async {
      var pulled = 0;
      for (final groupId in await discoverGroups()) {
        pulled += await pull(groupId);
      }
      return pulled;
    }),
  );

  Future<SyncReport> _run(Future<int> Function() pullGroups) async {
    final pushed = await push();
    try {
      await pullShared();
      final pulled = await pullGroups();
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

  /// Queues every run in this isolate and holds the platform's sync gate.
  ///
  /// The queue stops two foreground triggers racing; the gate covers what it
  /// cannot: an Android background isolate, or another browser tab.
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
          final report = await operation();
          return SyncReport(
            pushed: report.pushed,
            pulled: report.pulled,
            failed: report.failed,
            error: report.error,
            stackTrace: report.stackTrace,
            nextPushAt: await outbox.nextAttemptAt(),
          );
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

  /// Everything a pull needs that is not about one group.
  Future<void> pullShared() async {
    await pullReferenceData();
    await pullFxRates();
    await pullProfiles();
  }

  /// Currencies and categories. Must land before a group can be created,
  /// because `groups.default_currency` references `currencies`.
  ///
  /// Upsert, never delete: a withdrawn category is still on the entries that
  /// used it. Failures are swallowed here, where it is a refresh of data the
  /// device already has; `referenceDataProvider` calls it directly and does
  /// check, for the first launch.
  Future<void> pullReferenceData() async {
    try {
      final reference = await remote.reference().timeout(requestTimeout);
      await db.batch((batch) {
        for (final currency in reference.currencies) {
          batch.insert(
            db.currencies,
            currency.toRow(),
            onConflict: DoUpdate((_) => currency.toRow()),
          );
        }
        for (final category in reference.categories) {
          batch.insert(
            db.categories,
            category.toRow(),
            onConflict: DoUpdate((_) => category.toRow()),
          );
        }
      });
    } catch (_) {}
  }

  /// Whether this device knows what a currency is yet.
  Future<bool> hasReferenceData() async =>
      (await (db.select(db.currencies)..limit(1)).get()).isNotEmpty;

  /// A backstop on [push], not the thing that ends it.
  static const int _maxPushRounds = 50;

  /// Drains the outbox until nothing more is due.
  ///
  /// [OutboxQueue.due] answers a bounded page, so this loops. It terminates:
  /// each item is completed (deleted), backed off, or dead-lettered, and `due`
  /// excludes all three. The round cap only guards against a queue being
  /// refilled as fast as it drains.
  Future<({int sent, int failed})> push() async {
    var sent = 0;
    var failed = 0;

    for (var round = 0; round < _maxPushRounds; round++) {
      await _assertActive();
      final due = await outbox.due();
      if (due.isEmpty) break;

      for (final item in due) {
        try {
          await _pushOne(item);
          await outbox.complete(item);
          sent++;
        } on ApiFailure catch (e) {
          switch (e.retry) {
            case api.Retry.stale:
              await _parkConflict(item);
            case api.Retry.transient:
              await outbox.fail(item, e.message);
              return (sent: sent, failed: failed + 1);
            // Refused identically next time; retrying would wedge everything
            // queued behind it. A retry kind this build does not know is
            // treated the same way.
            case api.Retry.permanent:
            case api.Retry.unknownDefaultOpenApi:
              await outbox.fail(item, e.message, permanent: true);
          }
          failed++;
        } catch (e) {
          await outbox.fail(item, '$e');
          // A connection failure affects the whole batch; do not spend one
          // timeout per queued row.
          return (sent: sent, failed: failed + 1);
        }
      }
    }

    return (sent: sent, failed: failed);
  }

  /// Takes an edit the server refused as stale out of the queue and parks it
  /// for a person, then rewinds the group's cursor to the edit's base.
  ///
  /// The rewind is what makes the ledger converge. While the edit was queued,
  /// a pull skipped the server's newer version of this entry and moved the
  /// cursor past it; reading from the base again delivers it now that the row
  /// is no longer dirty. Re-applying the rows in between is idempotent.
  Future<void> _parkConflict(OutboxRow item) async {
    await db.transaction(() async {
      if (!await outbox.isCurrent(item)) return;
      final entry = await _loadEntry(item.targetId);
      if (entry == null) return;

      await db
          .into(db.entryConflicts)
          .insertOnConflictUpdate(
            EntryConflictsCompanion.insert(
              entryId: entry.id,
              groupId: entry.groupId,
              attempted: jsonEncode(snapshotOf(entry).toJson()),
              baseSeq: Value(entry.seq),
              rejectedAt: _clock(),
            ),
          );
      await _rewindCursor(entry.groupId, to: entry.seq ?? 0);
      await outbox.complete(item);
    });
  }

  /// Drops every write the server refused outright, and puts the server's
  /// version of those rows back.
  ///
  /// A row the server has is read again: its group's cursor goes back to just
  /// before this device's copy, so the next pull delivers the current one. A
  /// row the server never had exists nowhere else, so it is deleted. The
  /// exception is a member an expense still names, which is kept rather than
  /// breaking that expense.
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
        // The profile feed is cursored on time, not on seq: forget this
        // copy's timestamp and re-read the feed, so the server's copy wins.
        await (db.update(db.profiles)..where((t) => t.id.equals(id))).write(
          const ProfilesCompanion(updatedAt: Value(null)),
        );
        await (db.delete(
          db.feedCursors,
        )..where((t) => t.feed.equals(_profileFeed))).go();
    }
  }

  /// Removes the feed lines this device wrote for a change the server never
  /// accepted. A null [subjectId] means lines about the group itself.
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

  Future<void> _pushOne(OutboxRow item) async {
    switch (item.target) {
      case OutboxTarget.entry:
        // Read now, not at queue time: it may have been edited since.
        final entry = await _snapshot(item, () => _loadEntry(item.targetId));
        if (entry == null) return;

        // Created and deleted before its first push: nothing remote to delete.
        final base = entry.seq;
        if (entry.isDeleted && base == null) return;

        final stored =
            await (entry.isDeleted && base != null
                    ? remote.deleteEntry(entry.groupId, entry.id, baseSeq: base)
                    : remote.upsertEntry(entry.groupId, entry.toInput()))
                .timeout(requestTimeout);

        // The server's number is both this row's version and the base the
        // next edit is judged against.
        await db.transaction(() async {
          await _assertActive();
          await (db.update(db.entries)..where((t) => t.id.equals(stored.id)))
              .write(EntriesCompanion(seq: Value(stored.seq)));
        });

      case OutboxTarget.group:
        final group = await _snapshot(
          item,
          () => (db.select(
            db.groups,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (group == null) return;

        // A group the server has never seen is a create, which carries its
        // creator's member row in the same change.
        final creator = group.seq == null ? await _creatorOf(group) : null;
        final stored =
            await (creator == null
                    ? remote.updateGroup(group.id, group.toUpdate())
                    : remote.createGroup(group.toCreate(creator)))
                .timeout(requestTimeout);

        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.groups)..where((t) => t.id.equals(group.id)))
              .write(GroupsCompanion(seq: Value(stored.seq)));
          // The creator's row landed at the same number. Recording that stops
          // it being pushed again as somebody added afterwards.
          if (creator != null) {
            await (db.update(db.members)..where((t) => t.id.equals(creator.id)))
                .write(MembersCompanion(seq: Value(stored.seq)));
          }
        });

      case OutboxTarget.member:
        final member = await _snapshot(
          item,
          () => (db.select(
            db.members,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (member == null) return;

        final stored =
            await (member.seq == null
                    ? remote.addMember(member.groupId, member.toCreate())
                    : remote.updateMember(
                        member.groupId,
                        member.id,
                        member.toUpdate(),
                      ))
                .timeout(requestTimeout);

        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.members)..where((t) => t.id.equals(member.id)))
              .write(MembersCompanion(seq: Value(stored.seq)));
        });

      case OutboxTarget.profile:
        // Only ever this account's own row; the server refuses any other.
        final profile = await _snapshot(
          item,
          () => (db.select(
            db.profiles,
          )..where((t) => t.id.equals(item.targetId))).getSingleOrNull(),
        );
        if (profile == null) return;

        final stored = await remote
            .updateProfile(profile.toUpdate())
            .timeout(requestTimeout);
        await db.transaction(() async {
          if (!await outbox.isCurrent(item)) return;
          await (db.update(db.profiles)..where((t) => t.id.equals(profile.id)))
              .write(ProfilesCompanion(updatedAt: Value(stored.updatedAt)));
        });
    }
  }

  /// The group's creator, named by `createdBy` rather than guessed: a group
  /// created offline may already hold the whole trip.
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

  /// Applies one group's changes after its cursor, page by page.
  ///
  /// Counts entries only: the number that means "something happened to the
  /// money".
  Future<int> pull(String groupId) async {
    var cursor = await _readGroupCursor(groupId);
    var applied = 0;
    final claimed = <String>{};

    while (true) {
      await _assertActive();
      final page = await remote
          .changes(groupId, since: cursor, limit: pageSize)
          .timeout(requestTimeout);

      applied += await applyGroupChanges(db, page, now: _clock());
      claimed.addAll(page.members.map((member) => member.profileId).nonNulls);

      if (page.purgedAt != null) return applied;
      if (page.seq == cursor) break;
      cursor = page.seq;
      if (!page.hasMore) break;
    }

    await _hydrateProfiles(claimed);
    return applied;
  }

  /// Fetches profiles that became visible because a member row changed.
  ///
  /// Somebody claiming a placeholder may have an account named long ago, so
  /// their profile is older than this device's profile cursor and the feed
  /// will never mention it. Only profiles this device does not hold are
  /// asked for.
  Future<void> _hydrateProfiles(Set<String> profileIds) async {
    if (profileIds.isEmpty) return;

    final held = await (db.select(
      db.profiles,
    )..where((t) => t.id.isIn(profileIds))).get();
    final missing = profileIds.difference({for (final row in held) row.id});
    if (missing.isEmpty) return;

    await _assertActive();
    final list = await remote
        .profilesByIds(missing.toList()..sort())
        .timeout(requestTimeout);
    if (list.profiles.isEmpty) return;

    await db.transaction(() async {
      await _assertActive();
      await applyProfiles(db, list.profiles);
    });
  }

  Future<int> _readGroupCursor(String groupId) async {
    final row = await (db.select(
      db.groupCursors,
    )..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
    return row?.seq ?? 0;
  }

  /// The profile feed, on a `(timestamp, id)` keyset cursor.
  Future<int> pullProfiles() async {
    var (cursor, cursorId) = await _readFeedCursor(_profileFeed);
    var applied = 0;

    while (true) {
      await _assertActive();
      final resumable = cursor != null && cursorId != null;
      final page = await remote
          .profileChanges(
            since: resumable ? cursor : null,
            sinceId: resumable ? cursorId : null,
            limit: pageSize,
          )
          .timeout(requestTimeout);
      if (page.profiles.isEmpty) break;

      final at = page.cursor;
      final id = page.cursorId;
      applied += await db.transaction(() async {
        await _assertActive();
        final count = await applyProfiles(db, page.profiles);
        if (at != null && id != null) {
          await _writeFeedCursor(_profileFeed, at, id);
        }
        return count;
      });

      if (at == null || id == null || !page.hasMore) break;
      cursor = at;
      cursorId = id;
    }

    return applied;
  }

  /// Mirrors published exchange rates onto the device.
  ///
  /// Rates never change once published, so the ordinary ask is everything on
  /// or after the newest date held. It also reaches back once to the oldest
  /// expense that has no rate, because a backfill produces a date *older* than
  /// the newest held, which a high-water mark alone would never ask for.
  /// [_fxFloor] records how far back it has asked, so a date no provider
  /// answers widens the window once, not on every sync.
  ///
  /// Failure is swallowed: a missing rate costs an estimate, never a balance.
  Future<int> pullFxRates() async {
    try {
      final newest = await _newestRateDate();
      final since =
          await _oldestRateNeeded(newest) ??
          newest ??
          calendarDate(_clock().toUtc().subtract(_rateWindow));

      final page = await remote.fxRates(since: since).timeout(requestTimeout);
      await _writeFxFloor(since);
      if (page.rates.isEmpty) return 0;

      await db.transaction(() async {
        await _assertActive();
        await db.batch((batch) {
          for (final rate in page.rates) {
            batch.insert(
              db.fxRates,
              FxRatesCompanion.insert(
                asOf: rate.asOf,
                currency: rate.currency,
                rate: rate.rate.toDouble(),
                source: rate.source_,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });
      return page.rates.length;
    } catch (_) {
      return 0;
    }
  }

  /// How far back a device with no rates at all reaches on its first sync.
  static const _rateWindow = Duration(days: 400);

  /// The [FeedCursors] row recording how far back rates have been asked for.
  static const _fxFloor = 'fx:floor';

  /// The [FeedCursors] row for the profile feed.
  static const _profileFeed = 'profiles';

  /// The oldest day this device needs a rate for and has not asked about, or
  /// null in the steady state. Only entries in a currency other than their
  /// group's need one.
  Future<String?> _oldestRateNeeded(String? newest) async {
    final floor = (await _readFeedCursor(_fxFloor)).$2;

    final query =
        db.select(db.entries).join([
            innerJoin(db.groups, db.groups.id.equalsExp(db.entries.groupId)),
          ])
          ..where(
            db.entries.deletedAt.isNull() &
                db.entries.currency.isNotExp(db.groups.defaultCurrency),
          )
          ..orderBy([OrderingTerm.asc(db.entries.entryDate)])
          ..limit(1);

    final oldest = (await query.getSingleOrNull())
        ?.readTable(db.entries)
        .entryDate;
    if (oldest == null) return null;

    final wanted = calendarDate(oldest);
    if (newest != null && wanted.compareTo(newest) >= 0) return null;
    if (floor != null && wanted.compareTo(floor) >= 0) return null;
    return wanted;
  }

  /// Records how far back this device has asked, even when the answer was
  /// empty — that is the reason it exists.
  Future<void> _writeFxFloor(String since) async {
    final held = (await _readFeedCursor(_fxFloor)).$2;
    if (held != null && held.compareTo(since) <= 0) return;
    await _writeFeedCursor(_fxFloor, parseCalendarDate(since), since);
  }

  Future<String?> _newestRateDate() async {
    final row =
        await (db.select(db.fxRates)
              ..orderBy([(t) => OrderingTerm.desc(t.asOf)])
              ..limit(1))
            .getSingleOrNull();
    return row?.asOf;
  }

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

  /// Reads a row and checks the queue revision in one transaction, without
  /// holding it open across the network request.
  Future<T?> _snapshot<T>(OutboxRow item, Future<T?> Function() read) =>
      db.transaction(() async {
        await _assertActive();
        if (!await outbox.isCurrent(item)) return null;
        return read();
      });

  Future<(DateTime?, String?)> _readFeedCursor(String feed) async {
    final row = await (db.select(
      db.feedCursors,
    )..where((t) => t.feed.equals(feed))).getSingleOrNull();
    return (row?.cursor, row?.cursorId);
  }

  Future<void> _writeFeedCursor(String feed, DateTime at, String id) async {
    await db
        .into(db.feedCursors)
        .insertOnConflictUpdate(
          FeedCursorsCompanion.insert(
            feed: feed,
            cursor: Value(at),
            cursorId: Value(id),
            lastSyncedAt: Value(_clock()),
          ),
        );
  }
}
