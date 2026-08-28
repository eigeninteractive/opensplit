import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/fx/drift_fx_repository.dart';
import '../data/local/database.dart';
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
///
/// Synchronous on purpose: the database is keyed on it, and a database that
/// arrives one frame late would have every repository built against nothing.
/// The Supabase client restores its stored session during `Supabase.initialize`
/// — which `main` awaits — so by the time any of this runs the answer is
/// already known. Following the session keeps routing, sync, and the ledger on
/// the same identity, including immediately after a sign-in completes.
@Riverpod(keepAlive: true)
String? currentAccountId(Ref ref) => ref.watch(sessionControllerProvider)?.id;

/// This account's ledger, and no other account's.
///
/// Keyed by account rather than shared and wiped. The previous arrangement kept
/// one file, repointed its rows when an account arrived and erased them when a
/// different one took over, which was correct exactly as long as every path
/// remembered to do so. Naming the file after the account removes the question:
/// signing in as somebody else opens somebody else's file, and there is no
/// sequence of events that can show one person's expenses to another.
///
/// Switching is therefore non-destructive — the previous account's data is
/// still there if it comes back — and the price is that reference data is
/// per-account and re-pulled after a switch.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId == null) {
    // Nothing renders above this without a session: the router sends anyone
    // without one to the welcome screen. Reaching here means a provider was
    // read out of order, which is a bug rather than a state to handle.
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
///
/// Wired in from the start even though nothing drains it yet: every mutation is
/// queued as it happens, so when sync is switched on there is no backfill step
/// and nothing recorded in the meantime is lost. The queue coalesces per row,
/// so its size is bounded by how many rows were touched, not how many times.
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
///
/// Kept alive and watched app-wide for the same reason the dead letters are: a
/// parked edit is not a property of whichever group is open, and the person who
/// made it has no other way to find out it did not apply.
@Riverpod(keepAlive: true)
Stream<List<PendingConflict>> pendingConflicts(Ref ref) =>
    ref.watch(conflictRepositoryProvider).watchAll();

/// Writes the server refused outright, and will not accept on a retry.
///
/// Kept alive and watched app-wide rather than per screen: a refused write is
/// not a property of whichever group happens to be open, and the one thing that
/// must not happen is for it to go unmentioned because the user was elsewhere
/// when it failed.
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
///
/// No network: the server fetches rates centrally and they arrive with sync, so
/// a conversion works offline and every member of a group converts with the
/// same numbers.
@Riverpod(keepAlive: true)
DriftFxRepository fxRepository(Ref ref) =>
    DriftFxRepository(ref.watch(appDatabaseProvider));

/// The rate for one pair, as it stood on a given date.
///
/// Watched by the entry editor so the rate is already resolved by the time
/// anyone taps save. Null is an ordinary answer: a currency may have no
/// publication on or before that date, particularly for a backdated entry.
@riverpod
Future<FxQuote?> fxQuote(Ref ref, String base, String quote, DateTime asOf) =>
    ref.watch(fxRepositoryProvider).quote(base: base, quote: quote, asOf: asOf);

@Riverpod(keepAlive: true)
DriftProfileRepository profileRepository(Ref ref) => DriftProfileRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

/// Every profile this device knows about, keyed by id.
///
/// The join behind [GroupLedger.nameOf]: a member who has claimed an account
/// is displayed under that account's name, not under whatever a friend typed
/// when adding them.
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
