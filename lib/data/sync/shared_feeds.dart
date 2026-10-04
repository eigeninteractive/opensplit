import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/calendar_date.dart';
import '../local/database.dart';
import 'api_client.dart';
import 'apply_changes.dart';
import 'wire.dart';

/// The feeds that are not about one group: reference data, exchange rates and
/// profiles.
///
/// Reference data and rates are display aids, so their failures are logged
/// and never fail a sync that carries money.
class SharedFeeds {
  SharedFeeds({
    required this.db,
    required this.client,
    required this.clock,
    required this.requestTimeout,
    required this.pageSize,
    required this.assertActive,
  });

  final AppDatabase db;
  final api.OpensplitApi client;
  final DateTime Function() clock;
  final Duration requestTimeout;
  final int pageSize;

  /// Throws once the account's sync has ended, so a late response is dropped.
  final Future<void> Function() assertActive;

  /// How far back a device with no rates asks.
  static const _rateWindow = Duration(days: 400);

  static const _fxFloor = 'fx:floor';
  static const _profileFeed = 'profiles';
  static const _referenceTag = 'reference:etag';

  Future<void> pullAll() async {
    await pullReferenceData();
    await pullFxRates();
    await pullProfiles();
  }

  /// Currencies and categories, which must land before a group can be
  /// created. Upsert, never delete: a withdrawn category is still on the
  /// entries that used it. Asked for with the last copy's tag, so an
  /// unchanged list is a 304 with no body.
  Future<void> pullReferenceData() async {
    try {
      final held = await hasReferenceData()
          ? await _readCursor(_referenceTag)
          : null;
      final response = await client
          .getReferenceApi()
          .getReference(
            ifNoneMatch: held,
            validateStatus: (status) =>
                status != null && (status ~/ 100 == 2 || status == 304),
          )
          .timeout(requestTimeout);
      final reference = response.data;
      if (response.statusCode == 304 || reference == null) return;

      await db.batch((batch) {
        for (final currency in reference.currencies) {
          final row = currency.toRow().toCompanion(false);
          batch.insert(db.currencies, row, onConflict: DoUpdate((_) => row));
        }
        for (final category in reference.categories) {
          final row = category.toRow().toCompanion(false);
          batch.insert(db.categories, row, onConflict: DoUpdate((_) => row));
        }
      });
      if (response.headers.value('etag') case final tag?) {
        await _writeCursor(_referenceTag, tag);
      }
    } catch (error, stackTrace) {
      _log('Reference data was not refreshed', error, stackTrace);
    }
  }

  Future<bool> hasReferenceData() async =>
      (await (db.select(db.currencies)..limit(1)).get()).isNotEmpty;

  /// Rates after the newest one held, reaching back once to the oldest
  /// foreign-currency expense with no rate. The floor records how far back
  /// has been asked, so a day no provider answers widens the window once.
  Future<int> pullFxRates() async {
    try {
      final newest = await _newestRateDate();
      final since =
          await _oldestRateNeeded(newest) ??
          newest ??
          calendarDate(clock().toUtc().subtract(_rateWindow));

      final page = await fetch(
        client.getReferenceApi().getFxRates(since: since),
      ).timeout(requestTimeout);
      await _lowerFloor(since);
      if (page.rates.isEmpty) return 0;

      await db.transaction(() async {
        await assertActive();
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
    } catch (error, stackTrace) {
      _log('Exchange rates were not refreshed', error, stackTrace);
      return 0;
    }
  }

  /// Asks the server for a day it has never needed. Fire and forget: the rate
  /// arrives on a later sync.
  Future<void> requestBackfill(DateTime day, String currency) async {
    try {
      await fetch(
        client.getReferenceApi().requestFxBackfill(
          fxBackfillRequest: api.FxBackfillRequest(
            asOf: calendarDate(day),
            currency: currency,
          ),
        ),
      ).timeout(requestTimeout);
    } catch (error, stackTrace) {
      _log('A rate backfill was not requested', error, stackTrace);
    }
  }

  /// Everybody this account shares a group with, past the newest version
  /// already read.
  Future<int> pullProfiles() async {
    var since = int.tryParse(await _readCursor(_profileFeed) ?? '') ?? 0;
    var applied = 0;

    while (true) {
      await assertActive();
      final page = await fetch(
        client.getSyncApi().getProfiles(since: since, limit: pageSize),
      ).timeout(requestTimeout);
      if (page.profiles.isEmpty) break;

      applied += await db.transaction(() async {
        await assertActive();
        final count = await applyProfiles(db, page.profiles);
        await _writeCursor(_profileFeed, '${page.seq}');
        return count;
      });

      if (!page.hasMore || page.seq == since) break;
      since = page.seq;
    }
    return applied;
  }

  /// Forgets where the profile feed stands, so the next pull re-reads it.
  Future<void> resetProfileFeed() => (db.delete(
    db.feedCursors,
  )..where((t) => t.feed.equals(_profileFeed))).go();

  Future<String?> _oldestRateNeeded(String? newest) async {
    final floor = await _readCursor(_fxFloor);
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

  Future<void> _lowerFloor(String since) async {
    final held = await _readCursor(_fxFloor);
    if (held == null || since.compareTo(held) < 0) {
      await _writeCursor(_fxFloor, since);
    }
  }

  Future<String?> _newestRateDate() async {
    final row =
        await (db.select(db.fxRates)
              ..orderBy([(t) => OrderingTerm.desc(t.asOf)])
              ..limit(1))
            .getSingleOrNull();
    return row?.asOf;
  }

  Future<String?> _readCursor(String feed) async => (await (db.select(
    db.feedCursors,
  )..where((t) => t.feed.equals(feed))).getSingleOrNull())?.cursor;

  Future<void> _writeCursor(String feed, String cursor) => db
      .into(db.feedCursors)
      .insertOnConflictUpdate(
        FeedCursorsCompanion.insert(
          feed: feed,
          cursor: Value(cursor),
          lastSyncedAt: Value(clock()),
        ),
      );

  void _log(String message, Object error, StackTrace stackTrace) =>
      developer.log(
        message,
        name: 'opensplit.sync',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
}
