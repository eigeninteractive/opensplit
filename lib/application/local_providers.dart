import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/fx/drift_fx_repository.dart';
import '../data/local/database.dart';
import '../data/platform/device_time_zone.dart';
import '../data/repositories/drift_analytics_repository.dart';
import '../data/repositories/drift_category_repository.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_conflict_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_activity_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../data/sync/outbox_queue.dart';
import '../domain/fx/fx_quote.dart';
import 'session_providers.dart';

part 'local_providers.g.dart';

/// Who holds the session, synchronously.
@Riverpod(keepAlive: true)
String? currentAccountId(Ref ref) => ref.watch(sessionControllerProvider)?.id;

/// This device's IANA time zone: where an expense recorded here happened.
/// Null when the platform will not say.
@Riverpod(keepAlive: true)
Future<String?> deviceZone(Ref ref) => deviceTimeZone();

/// This account's ledger, and no other account's.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId == null) {
    // Nothing renders above this without a session: the router sends anyone
    // without one to the welcome screen.
    throw StateError(
      'There is no account, so there is no ledger to open. Something read a '
      'repository before anybody signed in.',
    );
  }
  final db = AppDatabase.forAccount(accountId);
  ref.onDispose(db.close);
  return db;
}

/// Pending writes waiting for a server.
@Riverpod(keepAlive: true)
OutboxQueue outboxQueue(Ref ref) {
  final queue = OutboxQueue(ref.watch(appDatabaseProvider));
  ref.onDispose(queue.dispose);
  return queue;
}

/// Edits the server refused because the expense had moved underneath them.
@Riverpod(keepAlive: true)
DriftConflictRepository conflictRepository(Ref ref) =>
    DriftConflictRepository(ref.watch(appDatabaseProvider));

/// The same, as they happen.
@Riverpod(keepAlive: true)
Stream<List<PendingConflict>> pendingConflicts(Ref ref) =>
    ref.watch(conflictRepositoryProvider).watchAll();

/// Writes the server refused outright, and will not accept on a retry.
@Riverpod(keepAlive: true)
Stream<List<FailedWrite>> failedWrites(Ref ref) =>
    ref.watch(outboxQueueProvider).watchDeadLetters();

@Riverpod(keepAlive: true)
DriftGroupRepository groupRepository(Ref ref) => DriftGroupRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

@Riverpod(keepAlive: true)
DriftEntryRepository entryRepository(Ref ref) => DriftEntryRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

@Riverpod(keepAlive: true)
DriftCurrencyRepository currencyRepository(Ref ref) =>
    DriftCurrencyRepository(ref.watch(appDatabaseProvider));

/// Display-only exchange rates, read from the locally mirrored table.
@Riverpod(keepAlive: true)
DriftFxRepository fxRepository(Ref ref) =>
    DriftFxRepository(ref.watch(appDatabaseProvider));

/// The rate for one pair, as it stood on a given date.
@riverpod
Future<FxQuote?> fxQuote(Ref ref, String base, String quote, DateTime asOf) =>
    ref.watch(fxRepositoryProvider).quote(base: base, quote: quote, asOf: asOf);

@Riverpod(keepAlive: true)
DriftProfileRepository profileRepository(Ref ref) => DriftProfileRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

/// Every profile this device knows about, keyed by id.
@Riverpod(keepAlive: true)
DriftActivityRepository activityRepository(Ref ref) =>
    DriftActivityRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
DriftCategoryRepository categoryRepository(Ref ref) =>
    DriftCategoryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
DriftAnalyticsRepository analyticsRepository(Ref ref) =>
    DriftAnalyticsRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(entryRepositoryProvider),
    );
