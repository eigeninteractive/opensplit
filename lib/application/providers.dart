import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../data/repositories/drift_analytics_repository.dart';
import '../data/repositories/drift_category_repository.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../data/auth/supabase_auth_service.dart';
import '../data/local/identity_reconciler.dart';
import '../data/push/push_service.dart';
import '../data/sync/outbox_queue.dart';
import '../data/sync/remote_ledger_api.dart';
import '../data/sync/supabase_invite_api.dart';
import '../data/sync/supabase_ledger_api.dart';
import '../data/sync/sync_engine.dart';
import '../domain/balance/balance_fold.dart';
import '../domain/balance/member_balance.dart';
import '../domain/balance/simplify.dart';
import '../domain/models/category.dart';
import '../domain/models/currency.dart';
import '../domain/models/entry.dart';
import '../domain/notification_text.dart';
import '../domain/models/group.dart';
import '../domain/money_format.dart';
import '../domain/models/member.dart';
import '../domain/models/profile.dart';
import '../domain/repositories/currency_repository.dart';
import '../domain/repositories/entry_repository.dart';
import '../domain/repositories/group_repository.dart';
import '../domain/repositories/analytics_repository.dart';
import '../domain/repositories/auth_service.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/repositories/invite_api.dart';
import '../domain/repositories/profile_repository.dart';

part 'providers.g.dart';

/// Overridden in `main` once the platform store has loaded.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
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
OutboxQueue outboxQueue(Ref ref) => OutboxQueue(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
GroupRepository groupRepository(Ref ref) => DriftGroupRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

@Riverpod(keepAlive: true)
EntryRepository entryRepository(Ref ref) => DriftEntryRepository(
  ref.watch(appDatabaseProvider),
  outbox: ref.watch(outboxQueueProvider),
);

@Riverpod(keepAlive: true)
CurrencyRepository currencyRepository(Ref ref) =>
    DriftCurrencyRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) =>
    DriftProfileRepository(ref.watch(appDatabaseProvider));

/// The stored profile for a member, when they have an account.
///
/// Placeholders have none, which is why this is nullable everywhere it is used
/// rather than something callers may assume exists.
@riverpod
Stream<Profile?> profile(Ref ref, String? profileId) => profileId == null
    ? Stream.value(null)
    : ref.watch(profileRepositoryProvider).watch(profileId);

/// Who this device is.
///
/// Before there is any account, the user still needs a stable identity so that
/// "you" can be picked out of a group's members. A locally generated id fills
/// that role and is written to `members.profile_id` exactly as a real account
/// id would be.
///
/// When a real account arrives, reconciling is one UPDATE over
/// `members.profile_id` — which is precisely the migration that group-scoped
/// members were chosen to make trivial.
class LocalIdentity {
  const LocalIdentity({
    required this.profileId,
    required this.displayName,
    this.upiVpa,
  });

  final String profileId;
  final String displayName;

  /// UPI virtual payment address, used to build settle-up handoffs.
  final String? upiVpa;

  bool get hasName => displayName.trim().isNotEmpty;
}

@Riverpod(keepAlive: true)
class LocalIdentityController extends _$LocalIdentityController {
  static const _profileIdKey = 'local_profile_id';
  static const _displayNameKey = 'local_display_name';
  static const _upiVpaKey = 'local_upi_vpa';

  @override
  LocalIdentity build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    var profileId = prefs.getString(_profileIdKey);
    if (profileId == null) {
      profileId = const Uuid().v4();
      prefs.setString(_profileIdKey, profileId);
    }

    return LocalIdentity(
      profileId: profileId,
      displayName: prefs.getString(_displayNameKey) ?? '',
      upiVpa: prefs.getString(_upiVpaKey),
    );
  }

  Future<void> setDisplayName(String name) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_displayNameKey, name.trim());
    state = LocalIdentity(
      profileId: state.profileId,
      displayName: name.trim(),
      upiVpa: state.upiVpa,
    );
    await _mirrorToProfile();
  }

  Future<void> setUpiVpa(String? vpa) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final trimmed = vpa?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_upiVpaKey);
    } else {
      await prefs.setString(_upiVpaKey, trimmed);
    }
    state = LocalIdentity(
      profileId: state.profileId,
      displayName: state.displayName,
      upiVpa: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _mirrorToProfile();
  }

  /// Replaces the locally generated id with a real account id.
  ///
  /// Called once, when a session first appears. Everything that referenced the
  /// old id has already been repointed by [adoptAuthIdentity].
  Future<void> adoptProfileId(String authUserId) async {
    if (state.profileId == authUserId) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_profileIdKey, authUserId);
    state = LocalIdentity(
      profileId: authUserId,
      displayName: state.displayName,
      upiVpa: state.upiVpa,
    );
    await _mirrorToProfile();
  }

  /// Mirrors the identity into the profiles table.
  ///
  /// Preferences hold this device's own settings, but the rest of the app looks
  /// people up by profile id — including the settle-up screen, which needs a
  /// payee's UPI handle. Writing it in one place keeps the two from drifting.
  Future<void> _mirrorToProfile() async {
    if (!state.hasName) return;
    await ref
        .read(profileRepositoryProvider)
        .upsert(
          Profile(
            id: state.profileId,
            displayName: state.displayName,
            upiVpa: state.upiVpa,
          ),
        );
  }
}

/// Currencies, keyed by code.
///
/// Exposed as a map so that no widget is ever more than a lookup away from the
/// exponent it needs to format an amount correctly.
@Riverpod(keepAlive: true)
Stream<Map<String, Currency>> currencies(Ref ref) => ref
    .watch(currencyRepositoryProvider)
    .watchAll()
    .map((list) => {for (final c in list) c.code: c});

@riverpod
Stream<List<Group>> groups(Ref ref, {bool includeArchived = false}) => ref
    .watch(groupRepositoryProvider)
    .watchGroups(includeArchived: includeArchived);

@riverpod
Stream<Group?> group(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchGroup(groupId);

@riverpod
Stream<List<Member>> members(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchMembers(groupId);

@riverpod
Stream<List<Entry>> entries(Ref ref, String groupId) =>
    ref.watch(entryRepositoryProvider).watchEntries(groupId);

/// Everything a group screen needs, folded once.
///
/// Balances and the settlement plan are derived here rather than stored, and
/// recomputed from the journal on every change. A stored balance has to be kept
/// in step with every edit, soft delete and late-arriving sync, and when it
/// drifts there is no way to tell that it has.
class GroupLedger {
  const GroupLedger({
    required this.group,
    required this.members,
    required this.entries,
    required this.balances,
    required this.transfers,
    required this.me,
  });

  final Group group;
  final List<Member> members;

  /// Live entries, most recent first.
  final List<Entry> entries;

  /// Net position per member per currency. Members who are settled are absent.
  final List<MemberBalance> balances;

  /// The suggested payments that would settle the group, per currency. Empty
  /// when the group has simplification switched off.
  final List<Transfer> transfers;

  /// This device's member in the group, if it has one.
  final Member? me;

  Member? memberById(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  String nameOf(String memberId) => memberById(memberId)?.displayName ?? '—';

  /// Currencies this group actually holds money in, in a stable order.
  List<String> get activeCurrencies {
    final codes = {for (final balance in balances) balance.currency};
    final ordered = codes.toList()..sort();
    return ordered;
  }

  int balanceOf(String memberId, String currency) {
    for (final balance in balances) {
      if (balance.memberId == memberId && balance.currency == currency) {
        return balance.balanceMinor;
      }
    }
    return 0;
  }

  bool get isSettled => balances.isEmpty;
}

/// The folded view of a group.
///
/// Null only in the frame before the local database answers. There is no
/// network in this path, so it is never a spinner the user can perceive.
@riverpod
GroupLedger? groupLedger(Ref ref, String groupId) {
  final group = ref.watch(groupProvider(groupId)).value;
  final memberList = ref.watch(membersProvider(groupId)).value;
  final entryList = ref.watch(entriesProvider(groupId)).value;
  if (group == null || memberList == null || entryList == null) return null;

  final identity = ref.watch(localIdentityControllerProvider);
  final balances = foldBalances(entryList);

  return GroupLedger(
    group: group,
    members: memberList,
    entries: entryList,
    balances: balances,
    transfers: group.simplifyDebts ? simplifyDebts(balances) : const [],
    me: memberList.where((m) => m.profileId == identity.profileId).firstOrNull,
  );
}

/// The backend client, or null when there is none.
///
/// Null is a supported state, not a failure: everything the product does is
/// computed on the device, so the app is fully usable with no server at all.
/// Only sync and accounts depend on this.
@Riverpod(keepAlive: true)
sb.SupabaseClient? supabaseClient(Ref ref) {
  try {
    return sb.Supabase.instance.client;
  } catch (_) {
    // Not initialised — a local-only build, or a test that never called
    // Supabase.initialize.
    return null;
  }
}

@Riverpod(keepAlive: true)
AuthService? authService(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthService(client);
}

@Riverpod(keepAlive: true)
InviteApi? inviteApi(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseInviteApi(client);
}

@Riverpod(keepAlive: true)
RemoteLedgerApi? remoteLedgerApi(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseLedgerApi(client);
}

@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final api = ref.watch(remoteLedgerApiProvider);
  if (api == null) return null;
  return SyncEngine(
    db: ref.watch(appDatabaseProvider),
    api: api,
    outbox: ref.watch(outboxQueueProvider),
  );
}

/// The current session, if any.
@Riverpod(keepAlive: true)
Stream<Account?> account(Ref ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) return Stream.value(null);
  return auth.authStateChanges();
}

/// Establishes a session and reconciles this device's local identity with it.
///
/// Anonymous sign-in happens silently and is never presented as a step. Someone
/// arriving from an invite link has to land inside the group; a signup screen at
/// that moment is where they leave.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  Future<Account?> build() async {
    final auth = ref.watch(authServiceProvider);
    if (auth == null) return null;

    final user = auth.currentUser ?? await auth.signInAnonymously();

    // Everything recorded before this session existed was filed under a locally
    // generated id. Move it across — one column, no financial rows touched.
    final identity = ref.read(localIdentityControllerProvider);
    if (identity.profileId != user.id) {
      await adoptAuthIdentity(
        ref.read(appDatabaseProvider),
        localProfileId: identity.profileId,
        authUserId: user.id,
        outbox: ref.read(outboxQueueProvider),
      );
      await ref
          .read(localIdentityControllerProvider.notifier)
          .adoptProfileId(user.id);
    }

    return user;
  }
}

/// Runs sync and reports what happened.
///
/// Deliberately manual rather than a persistent realtime subscription: peak
/// concurrent realtime peers is what a hosted backend bills for, and pushing a
/// wake-up costs nothing. Live subscriptions are reserved for the rare case of
/// two people editing the same group at the same moment.
@riverpod
class SyncController extends _$SyncController {
  @override
  SyncReport? build() => null;

  Future<void> syncGroup(String groupId) async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;

    // Make sure a session exists first, or every push is refused by RLS.
    await ref.read(sessionControllerProvider.future);

    state = await engine.syncGroup(groupId);
  }

  Future<void> syncAll() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    await ref.read(sessionControllerProvider.future);

    final groups = await ref.read(groupRepositoryProvider).watchGroups().first;
    for (final group in groups) {
      state = await engine.syncGroup(group.id);
    }
  }
}

/// Syncs a group when its screen opens.
///
/// A provider rather than an initState call so it runs once per mount, is
/// cancelled with the screen, and is trivially overridable in tests. Failures
/// are swallowed on purpose: the screen renders entirely from the local
/// database, so a sync that cannot reach the server changes nothing the user
/// can see and must not produce an error surface.
@riverpod
Future<void> groupSync(Ref ref, String groupId) async {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return;
  try {
    await ref.read(sessionControllerProvider.future);
    await engine.syncGroup(groupId);
  } catch (_) {
    // Offline is the normal case, not an error.
  }
}

/// How many entries this device has recorded, across every group.
///
/// Drives the prompt to attach an account. Anonymous means one device and no
/// recovery — on the web, clearing site data destroys it outright — so the ask
/// has to arrive once there is something worth losing, and never before.
@riverpod
Future<int> totalEntryCount(Ref ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.select(db.entries).get();
  return rows.where((row) => row.deletedAt == null).length;
}

@Riverpod(keepAlive: true)
CategoryRepository categoryRepository(Ref ref) =>
    DriftCategoryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
AnalyticsRepository analyticsRepository(Ref ref) =>
    DriftAnalyticsRepository(ref.watch(appDatabaseProvider));

/// Categories a group can use: the global presets plus its own additions.
@riverpod
Stream<List<Category>> groupCategories(Ref ref, String groupId) =>
    ref.watch(categoryRepositoryProvider).watchForGroup(groupId);

/// The current analytics question. Held in a provider so the filter survives
/// navigating into an entry and back out.
@riverpod
class AnalyticsFilterController extends _$AnalyticsFilterController {
  @override
  AnalyticsFilter build(String groupId) => AnalyticsFilter(groupId: groupId);

  void update(AnalyticsFilter filter) => state = filter;
  void reset() => state = AnalyticsFilter(groupId: groupId);
}

@riverpod
Future<List<SpendBucket>> spendByCategory(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByCategory(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Future<List<SpendBucket>> spendByMember(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByMember(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Future<List<SpendBucket>> spendByMonth(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByMonth(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Future<List<Entry>> analyticsResults(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .search(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Future<List<String>> groupCurrencies(Ref ref, String groupId) =>
    ref.watch(analyticsRepositoryProvider).currenciesUsed(groupId);

/// Push, wired to sync first and describe second.
///
/// The message from the server carries only ids. Everything the notification
/// says is produced here, from data that has just been pulled onto this device,
/// using the same formatter the screens use.
@Riverpod(keepAlive: true)
PushService pushService(Ref ref) => PushService(
  onWake: (groupId) async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    await engine.syncGroup(groupId);
  },
  describe: (groupId, entryId) async {
    final entry = await ref.read(entryRepositoryProvider).getEntry(entryId);
    if (entry == null) return null;

    final group = await ref.read(groupRepositoryProvider).getGroup(groupId);
    final members = await ref.read(groupRepositoryProvider).getMembers(groupId);
    final currencies = await ref.read(currencyRepositoryProvider).all();
    final me = ref.read(localIdentityControllerProvider).profileId;

    String nameOf(String memberId) =>
        members
            .where((m) => m.id == memberId)
            .map((m) => m.displayName)
            .firstOrNull ??
        'Someone';

    final myMemberId = members
        .where((m) => m.profileId == me)
        .map((m) => m.id)
        .firstOrNull;
    final myShare =
        entry.shares
            .where((s) => s.memberId == myMemberId)
            .map((s) => s.amountMinor)
            .firstOrNull ??
        0;

    final currency = currencies
        .where((c) => c.code == entry.currency)
        .firstOrNull;

    return describeEntry(
      entry: entry,
      groupName: group?.name ?? 'OpenSplit',
      authorName: nameOf(entry.createdBy),
      currency: currency,
      shareMinor: myShare,
      // The screens' formatter, so a banner and the app can never quote
      // different figures.
      format: (minor) => formatMoney(currency, minor),
    );
  },
);

/// Registers this device for push, once there is a session to attach it to.
///
/// Failure is not surfaced: push is a convenience on top of sync, and a device
/// that cannot register still receives everything the next time a screen opens.
@Riverpod(keepAlive: true)
Future<void> pushRegistration(Ref ref) async {
  final account = await ref.watch(sessionControllerProvider.future);
  final client = ref.watch(supabaseClientProvider);
  if (account == null || client == null) return;

  try {
    final push = ref.read(pushServiceProvider);
    await push.initialize();

    final token = await push.token();
    if (token == null) return;

    await client.from('device_tokens').upsert({
      'token': token,
      'profile_id': account.id,
      'platform': push.platform,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });
  } catch (error) {
    // Push is not configured, or permission was refused. Neither is a problem
    // worth interrupting anyone about.
  }
}
