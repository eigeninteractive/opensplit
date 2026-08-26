import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import 'entry_notification.dart';
import '../data/fx/drift_fx_repository.dart';
import '../data/local/database.dart';
import '../data/repositories/drift_analytics_repository.dart';
import '../data/repositories/drift_category_repository.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../data/auth/supabase_auth_service.dart';
import '../data/local/identity_reconciler.dart';
import '../data/local/local_reset.dart';
import '../data/push/push_service.dart';
import '../data/sync/outbox_queue.dart';
import '../data/sync/remote_ledger_api.dart';
import '../data/sync/supabase_invite_api.dart';
import '../data/sync/supabase_ledger_api.dart';
import '../data/sync/sync_engine.dart';
import '../domain/balance/balance_fold.dart';
import '../domain/fx/estimated_total.dart';
import '../domain/fx/fx_quote.dart';
import '../domain/balance/member_balance.dart';
import '../domain/balance/simplify.dart';
import '../domain/models/category.dart';
import '../domain/models/currency.dart';
import '../domain/models/entry.dart';
import '../domain/models/group.dart';
import '../domain/models/member.dart';
import '../domain/models/profile.dart';
import '../domain/analytics/analytics_query.dart';
import '../domain/repositories/auth_service.dart';
import '../domain/repositories/invite_api.dart';
import '../presentation/router.dart';

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
DriftProfileRepository profileRepository(Ref ref) =>
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
    this.isAccount = false,
  });

  final String profileId;
  final String displayName;

  /// UPI virtual payment address, used to build settle-up handoffs.
  final String? upiVpa;

  /// Whether [profileId] is a real account id rather than the locally invented
  /// one this device starts with.
  ///
  /// The distinction decides whether a change of id is a promotion or a
  /// switch. A locally invented id becoming an account id is the first case,
  /// and everything filed under the old one is repointed. One account id
  /// becoming a different account id is the second, and repointing would hand
  /// somebody else's rows to whoever just signed in — rows the server will
  /// refuse anyway, since they still belong to the account that wrote them.
  final bool isAccount;

  bool get hasName => displayName.trim().isNotEmpty;
}

@Riverpod(keepAlive: true)
class LocalIdentityController extends _$LocalIdentityController {
  static const _profileIdKey = 'local_profile_id';
  static const _displayNameKey = 'local_display_name';
  static const _upiVpaKey = 'local_upi_vpa';
  static const _isAccountKey = 'local_profile_is_account';

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
      isAccount: prefs.getBool(_isAccountKey) ?? false,
    );
  }

  Future<void> setDisplayName(String name) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_displayNameKey, name.trim());
    state = LocalIdentity(
      profileId: state.profileId,
      displayName: name.trim(),
      upiVpa: state.upiVpa,
      isAccount: state.isAccount,
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
      isAccount: state.isAccount,
    );
    await _mirrorToProfile();
  }

  /// Points this device at [authUserId].
  ///
  /// Called when a session first appears, and again if a different account ever
  /// takes the session over. Whether the rows filed under the previous id come
  /// with it is [adoptAuthIdentity]'s decision, not this one's — see
  /// [LocalIdentity.isAccount].
  Future<void> adoptProfileId(String authUserId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    // Written even when the id is unchanged: the very first anonymous session
    // adopts an id this device invented, and the fact that it is now an account
    // is the thing worth remembering.
    await prefs.setBool(_isAccountKey, true);
    if (state.profileId == authUserId) {
      state = LocalIdentity(
        profileId: state.profileId,
        displayName: state.displayName,
        upiVpa: state.upiVpa,
        isAccount: true,
      );
      return;
    }

    await prefs.setString(_profileIdKey, authUserId);
    state = LocalIdentity(
      profileId: authUserId,
      displayName: state.displayName,
      upiVpa: state.upiVpa,
      isAccount: true,
    );
    await _mirrorToProfile();
  }

  /// Forgets the name and handle this device was using, keeping its id.
  ///
  /// Part of switching to an account that already exists: the display name and
  /// UPI handle belonged to whoever was using the device before, and carrying
  /// them into somebody else's session would put a stranger's payment address
  /// on their settle-up screen.
  Future<void> clearPersonalDetails() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_upiVpaKey);
    state = LocalIdentity(
      profileId: state.profileId,
      displayName: '',
      isAccount: state.isAccount,
    );
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

/// This device's own balance across every currency, as one estimated figure.
///
/// Null whenever an estimate would be meaningless or misleading — no member,
/// only one currency in play (where the exact per-currency figure is already
/// the whole answer), or no rate for anything. Callers render nothing in that
/// case rather than a zero, because "we could not convert this" and "you are
/// settled" are very different statements to make about someone's money.
///
/// Synchronous, and no longer touches the rate table: every rate it needs is
/// already stamped on the entry that used it.
@riverpod
EstimatedTotal? groupEstimate(Ref ref, String groupId) {
  final ledger = ref.watch(groupLedgerProvider(groupId));
  final currencies = ref.watch(currenciesProvider).value;
  if (ledger == null || currencies == null) return null;

  final me = ledger.me;
  if (me == null) return null;

  // One currency means the exact figure beneath this is already the answer, and
  // repeating it approximately would only invite doubt about which to believe.
  final holding = ledger.activeCurrencies
      .where((code) => ledger.balanceOf(me.id, code) != 0)
      .toSet();
  if (holding.length < 2) return null;

  return estimateBalance(
    entries: ledger.entries,
    memberId: me.id,
    target: ledger.group.defaultCurrency,
    currencies: currencies,
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
/// Anonymous sign-in happens silently and is never presented as a step.
/// Someone arriving from an invite link has to land inside the group; a signup
/// screen at that moment is where they leave.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  Future<Account?> build() async {
    final auth = ref.watch(authServiceProvider);
    if (auth == null) return null;

    final user = auth.currentUser ?? await auth.signInAnonymously();

    final identity = ref.read(localIdentityControllerProvider);
    if (identity.profileId != user.id) {
      // Everything recorded before this session existed was filed under a
      // locally generated id. Move it across — one column, no financial rows
      // touched.
      //
      // Only from a locally invented id, though. If this device was already an
      // account and a different one now holds the session, the rows filed under
      // the old id are not this account's to take: the server still has them
      // under the previous user and refuses every write made under the new one.
      // That path wipes instead, in AccountController.
      if (!identity.isAccount) {
        await adoptAuthIdentity(
          ref.read(appDatabaseProvider),
          localProfileId: identity.profileId,
          authUserId: user.id,
          outbox: ref.read(outboxQueueProvider),
        );
      }
      await ref
          .read(localIdentityControllerProvider.notifier)
          .adoptProfileId(user.id);
    } else if (!identity.isAccount) {
      // Same id, but this is the first time it has been backed by a session.
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

  /// Syncs every group this account belongs to, including ones this device has
  /// never seen.
  ///
  /// The list comes from the server, not from the local database. Sweeping
  /// local groups only is what made a second device — and a reinstall, and
  /// signing in after clearing browser data — show an empty app forever: the
  /// groups were on the server, readable, and nothing ever asked for them.
  Future<void> syncAll() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    await ref.read(sessionControllerProvider.future);

    for (final groupId in await engine.discoverGroups()) {
      state = await engine.syncGroup(groupId);
    }
  }

  /// Requeues everything the server previously refused and pushes again.
  ///
  /// Whatever made the server say no may have been fixed since — most often by
  /// a membership row that had not landed yet. If it has not, the items simply
  /// fail the same way and are set aside again, which is why this is safe to
  /// offer as a button.
  Future<void> retryFailed() async {
    await ref.read(outboxQueueProvider).retryDeadLetters();
    await syncAll();
  }
}

/// Attaching a real account to this device, and the sign-in it sometimes turns
/// out to be instead.
///
/// The two outcomes are opposites and the difference is the whole reason this
/// exists rather than the screen calling [AuthService] directly. Linking keeps
/// the user id, so every group, member and expense on this device stays exactly
/// where it is. Signing in as an account that already exists replaces the
/// session, and those rows are then unreachable: the server holds them under
/// the anonymous user that wrote them, and row-level security refuses every
/// write made under the new one. Keeping them on screen would produce a group
/// list where some rows sync and some never can, with nothing to say which.
///
/// So a sign-in wipes the device first — after the screen has said so and been
/// answered — and re-syncs from the server as the account that now holds it.
@Riverpod(keepAlive: true)
class AccountController extends _$AccountController {
  @override
  void build() {}

  /// How many expenses signing in as somebody else would leave behind.
  ///
  /// Used to make the warning specific. "You will lose what is on this device"
  /// is ignorable; "the 34 expenses on this device stay with the anonymous
  /// account" is not.
  Future<int> entriesLeftBehind() async {
    final db = ref.read(appDatabaseProvider);
    final rows = await db.select(db.entries).get();
    return rows.where((row) => row.deletedAt == null).length;
  }

  AuthService _auth() {
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      throw StateError('This build has no backend, so it has no accounts.');
    }
    return auth;
  }

  Future<EmailFlow> sendEmailCode(String email) async {
    final auth = _auth();
    // There has to be a session to attach the address to.
    await ref.read(sessionControllerProvider.future);
    return auth.sendEmailCode(email);
  }

  Future<IdentityOutcome> verifyEmailCode({
    required String email,
    required String code,
    required EmailFlow flow,
  }) async {
    final outcome = await _auth().verifyEmailCode(
      email: email,
      code: code,
      flow: flow,
    );
    await _settle(outcome);
    return outcome;
  }

  /// Throws [IdentityAlreadyInUse] unless [allowSignIn], so the screen gets a
  /// chance to say what signing in would cost before the session is replaced.
  Future<IdentityOutcome> continueWithGoogle({
    required String idToken,
    String? accessToken,
    bool allowSignIn = false,
  }) async {
    await ref.read(sessionControllerProvider.future);
    final outcome = await _auth().continueWithGoogle(
      idToken: idToken,
      accessToken: accessToken,
      allowSignIn: allowSignIn,
    );
    await _settle(outcome);
    return outcome;
  }

  /// Brings the device into line with whatever just happened to the session.
  Future<void> _settle(IdentityOutcome outcome) async {
    if (!outcome.keptTheSession) {
      await forgetLocalLedger(ref.read(appDatabaseProvider));
      await ref
          .read(localIdentityControllerProvider.notifier)
          .clearPersonalDetails();
    }

    // Before the session is rebuilt, so SessionController sees an identity that
    // already matches and does not try to repoint anything.
    await ref
        .read(localIdentityControllerProvider.notifier)
        .adoptProfileId(outcome.account.id);

    ref.invalidate(sessionControllerProvider);
    await ref.read(syncControllerProvider.notifier).syncAll();
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
DriftCategoryRepository categoryRepository(Ref ref) =>
    DriftCategoryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
DriftAnalyticsRepository analyticsRepository(Ref ref) =>
    DriftAnalyticsRepository(ref.watch(appDatabaseProvider));

/// The fixed global category list. Not group-scoped: there are no per-group
/// categories, so this is one query for the whole app.
@riverpod
Stream<List<Category>> categories(Ref ref) =>
    ref.watch(categoryRepositoryProvider).watchAll();

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
PushService pushService(Ref ref) {
  final service = PushService(
    onTokenChanged: (token) => _registerDeviceToken(ref, token),
    onWake: (groupId) async {
      final engine = ref.read(syncEngineProvider);
      if (engine == null) return;
      await engine.syncGroup(groupId);
    },
    // The same composer the background isolate calls, so a notification says
    // the same thing whether the app was open when it arrived or not.
    describe: (groupId, entryId) => composeEntryNotification(
      entries: ref.read(entryRepositoryProvider),
      groups: ref.read(groupRepositoryProvider),
      currencies: ref.read(currencyRepositoryProvider),
      myProfileId: ref.read(localIdentityControllerProvider).profileId,
      groupId: groupId,
      entryId: entryId,
    ),
    onOpenRoute: (route) => ref.read(routerProvider).go(route),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// The one router instance.
///
/// A provider rather than a field on the app widget's state so that things
/// outside the widget tree can navigate — specifically a notification tap,
/// which arrives from the OS with no `BuildContext` anywhere in sight.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) => buildRouter();

/// Sends this device's token to the server.
///
/// Shared by first registration and by the rotation listener, so both write the
/// same row the same way.
Future<void> _registerDeviceToken(Ref ref, String token) async {
  final client = ref.read(supabaseClientProvider);
  final account = await ref.read(sessionControllerProvider.future);
  if (client == null || account == null) return;

  // An RPC rather than an upsert, because a device changes hands. Signing in
  // as a different account, or reinstalling, gets the same registration back
  // from FCM while the stored row still names the previous owner — and RLS
  // evaluates an upsert's UPDATE half against that row and refuses it. The
  // symptom is a device that silently stops receiving anything.
  //
  // register_device_token always writes auth.uid(), so the takeover is the
  // only thing it can do.
  await client.rpc(
    'register_device_token',
    params: {
      'p_token': token,
      'p_platform': ref.read(pushServiceProvider).platform,
    },
  );
}

/// Registers this device for push, if the user has already agreed to it.
///
/// Deliberately does NOT ask for permission. Asking is a separate, explicit
/// action taken from Settings or from the invite flow — see
/// [PushService.requestPermission]. This provider only wires up an
/// already-granted permission, so a launch never produces a system dialog.
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
    // Sets up listeners only. Safe to run before any permission exists, and
    // necessary so that a permission granted in system settings starts working
    // on the next launch without another prompt.
    await push.initialize();
    if (!await push.hasPermission()) return;

    final token = await push.token();
    if (token == null) return;
    await _registerDeviceToken(ref, token);
  } catch (error) {
    // Push is not configured, or permission was refused. Neither is a problem
    // worth interrupting anyone about.
  }
}

/// Whether the user has asked to be told about group activity.
///
/// Persisted separately from the OS permission because they answer different
/// questions: the OS knows whether the app *may* post a notification, this
/// knows whether the user ever *wanted* one. Keeping both means the Settings
/// switch can show the real state after someone revokes permission in system
/// settings, instead of silently claiming notifications are on.
@Riverpod(keepAlive: true)
class NotificationPreference extends _$NotificationPreference {
  static const _key = 'notifications_requested';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  /// Whether the user has ever been shown the prompt.
  ///
  /// Distinct from the stored value being false, which means they were asked
  /// and said no — a state that must not be re-prompted unbidden.
  bool get hasBeenAsked =>
      ref.read(sharedPreferencesProvider).containsKey(_key);

  /// Records a refusal made in the app, before the OS is ever involved.
  Future<void> markDeclined() => _remember(false);

  /// Turns notifications on, prompting the OS if needed.
  ///
  /// Returns whether they are actually on afterwards, which is not the same as
  /// what the user tapped: on Android 13+ a second refusal makes the system
  /// dialog stop appearing entirely, so this can return false having shown the
  /// user nothing at all. Callers say so rather than leaving a switch on.
  Future<bool> enable() async {
    final push = ref.read(pushServiceProvider);
    final granted = await push.requestPermission();
    await _remember(granted);
    if (!granted) return false;

    final token = await push.token();
    if (token == null) return false;
    await _registerDeviceToken(ref, token);
    return true;
  }

  /// Stops notifying this device, and removes its token from the server so the
  /// fan-out does not keep paying to wake a device that will ignore it.
  Future<void> disable() async {
    await _remember(false);
    final client = ref.read(supabaseClientProvider);
    final token = await ref.read(pushServiceProvider).token();
    if (client == null || token == null) return;
    try {
      await client.from('device_tokens').delete().eq('token', token);
    } catch (_) {
      // The preference is what governs this device either way.
    }
  }

  Future<void> _remember(bool wanted) async {
    await ref.read(sharedPreferencesProvider).setBool(_key, wanted);
    state = wanted;
  }
}
