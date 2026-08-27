import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'entry_notification.dart';
import '../data/fx/drift_fx_repository.dart';
import '../data/local/database.dart';
import '../data/repositories/drift_analytics_repository.dart';
import '../data/repositories/drift_category_repository.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_activity_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../data/auth/supabase_auth_service.dart';
import '../data/local/local_reset.dart';
import '../data/network/network_signal.dart';
import '../data/platform/app_update_service.dart';
import '../data/platform/review_prompt.dart';
import '../data/push/push_service.dart';
import '../data/sync/outbox_queue.dart';
import '../data/sync/remote_ledger_api.dart';
import '../data/sync/supabase_invite_api.dart';
import '../data/sync/supabase_ledger_api.dart';
import '../data/sync/sync_engine.dart';
import '../domain/balance/balance_fold.dart';
import 'sync_scheduler.dart';
import '../domain/fx/estimated_total.dart';
import '../domain/fx/fx_quote.dart';
import '../domain/balance/member_balance.dart';
import '../domain/balance/simplify.dart';
import '../domain/models/category.dart';
import '../domain/models/currency.dart';
import '../domain/models/entry.dart';
import '../domain/models/entry_event.dart';
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

/// Who holds the session, synchronously.
///
/// Synchronous on purpose: the database is keyed on it, and a database that
/// arrives one frame late would have every repository built against nothing.
/// The Supabase client restores its stored session during `Supabase.initialize`
/// — which `main` awaits — so by the time any of this runs the answer is
/// already known. Watching the auth stream is what makes it react afterwards.
@Riverpod(keepAlive: true)
String? currentAccountId(Ref ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) return null;
  // Rebuilds this provider — and therefore the database below it — whenever the
  // session changes.
  ref.watch(accountProvider);
  return auth.currentUser?.id;
}

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

/// Every profile this device knows about, keyed by id.
///
/// The join behind [GroupLedger.nameOf]: a member who has claimed an account
/// is displayed under that account's name, not under whatever a friend typed
/// when adding them.
@Riverpod(keepAlive: true)
DriftActivityRepository activityRepository(Ref ref) =>
    DriftActivityRepository(ref.watch(appDatabaseProvider));

/// A group's activity feed, newest first.
@riverpod
Stream<List<EntryEvent>> groupActivity(Ref ref, String groupId) =>
    ref.watch(activityRepositoryProvider).watchGroup(groupId);

/// One expense's history, in the order it happened.
@riverpod
Stream<List<EntryEvent>> entryActivity(Ref ref, String entryId) =>
    ref.watch(activityRepositoryProvider).watchEntry(entryId);

@riverpod
Stream<Map<String, Profile>> profilesById(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchAll();

/// The stored profile for a member, when they have an account.
///
/// Placeholders have none, which is why this is nullable everywhere it is used
/// rather than something callers may assume exists.
@riverpod
Stream<Profile?> profile(Ref ref, String? profileId) => profileId == null
    ? Stream.value(null)
    : ref.watch(profileRepositoryProvider).watch(profileId);

/// This account's own name and payment handle.
///
/// The `profiles` row is the source of truth, not a preference on this device.
/// That is what makes a rename propagate: co-members can already read each
/// other's profiles, so the name travels with the next sync instead of being
/// a copy frozen into whichever group happened to be open when it was typed.
///
/// It also means there is exactly one name. There used to be three — a
/// preference, a `profiles` row mirrored from it, and a `members.display_name`
/// per group — and nothing kept them in step.
@riverpod
Stream<Profile?> myProfile(Ref ref) {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId == null) return Stream.value(null);
  return ref.watch(profileRepositoryProvider).watch(accountId);
}

/// Editing your own profile.
@riverpod
class MyProfileController extends _$MyProfileController {
  @override
  void build() {}

  /// Saves both fields together, because the screen edits them together.
  ///
  /// Values are built explicitly rather than with `copyWith`, which cannot set
  /// a nullable field back to null — passing null there means "leave it alone",
  /// so clearing a payment handle would silently do nothing.
  Future<void> save({required String displayName, String? upiVpa}) async {
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId == null) return;

    final profiles = ref.read(profileRepositoryProvider);
    final current = await profiles.byId(accountId);
    final handle = upiVpa?.trim();

    await profiles.upsert(
      Profile(
        id: accountId,
        displayName: displayName.trim(),
        avatarUrl: current?.avatarUrl,
        upiVpa: handle == null || handle.isEmpty ? null : handle,
      ),
    );

    // Queued rather than pushed, so renaming while offline is as ordinary as
    // renaming while online. Co-members see it on their next sync: they can
    // already read each other's profiles, which is what makes one edit here
    // reach everybody without a copy per group.
    await ref
        .read(outboxQueueProvider)
        .enqueue(OutboxTarget.profile, accountId);
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

/// Everybody who has ever been in the group, departed members included.
///
/// [GroupLedger] splits them: rosters and pickers get the active ones, and name
/// resolution gets all of them. Fetching only the active ones is what made a
/// departed member's outstanding balance render as "—" — the balances panel
/// iterates balances, not members, and a member it could not find had no name
/// to show.
@riverpod
Stream<List<Member>> members(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchMembers(groupId, includeLeft: true);

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
    required this.pastMembers,
    required this.entries,
    required this.balances,
    required this.transfers,
    required this.me,
    required this.profiles,
    required this.brokenEntries,
  });

  final Group group;

  /// Members still in the group. What a roster, a picker or a split offers.
  final List<Member> members;

  /// Members who have left. Never offered as a choice, but still resolvable by
  /// name: they appear in past expenses, and — if they left without settling —
  /// in the balances.
  final List<Member> pastMembers;

  /// Live entries, most recent first.
  final List<Entry> entries;

  /// Net position per member per currency. Members who are settled are absent.
  final List<MemberBalance> balances;

  /// The suggested payments that would settle the group, per currency. Empty
  /// when the group has simplification switched off.
  final List<Transfer> transfers;

  /// This device's member in the group, if it has one.
  final Member? me;

  /// Accounts belonging to the members of this group, keyed by profile id.
  final Map<String, Profile> profiles;

  /// Entries whose payers and shares do not add up to their own total.
  ///
  /// Empty in every ordinary case — nothing in this app can write one. It is
  /// carried on the ledger rather than checked where it is displayed because
  /// the consequence is otherwise invisible: [balances] would still render, and
  /// [transfers] would quietly come back short or empty, so the group would
  /// show what everyone owes and offer no way to settle it.
  final List<Entry> brokenEntries;

  /// Whether the balances on this ledger can be trusted to add up.
  bool get isCoherent => brokenEntries.isEmpty;

  /// What to call [member], and where to pay them.
  ///
  /// A member's own name and payment handle are placeholder storage, used only
  /// while nobody has claimed the place. Once somebody has, their account
  /// answers both — one name, one payment identity, edited once on the Account
  /// screen and true everywhere, including in other people's copies of the
  /// group.
  ///
  /// Falls back to the member row when the profile has not synced yet, which is
  /// the ordinary state for a few seconds after somebody accepts an invite.
  String nameOfMember(Member member) {
    final claimed = profiles[member.profileId]?.displayName?.trim() ?? '';
    return claimed.isEmpty ? member.displayName : claimed;
  }

  String? upiOf(Member member) =>
      profiles[member.profileId]?.upiVpa ?? member.upiVpa;

  /// Looks through departed members too. A name is needed wherever an id
  /// appears, and ids outlive membership by design.
  Member? memberById(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    for (final member in pastMembers) {
      if (member.id == id) return member;
    }
    return null;
  }

  /// Whether [memberId] is square with the group in every currency.
  ///
  /// [balances] holds only non-zero positions, so absence is the definition of
  /// settled — the same one `v_member_balances` uses, and the same one the
  /// server checks before letting anybody remove somebody else.
  bool isSettledUp(String memberId) =>
      !balances.any((balance) => balance.memberId == memberId);

  String nameOf(String memberId) {
    final member = memberById(memberId);
    return member == null ? '—' : nameOfMember(member);
  }

  /// What to print against a change in the activity feed.
  ///
  /// [memberId] is null when the change reached the server from something with
  /// no member row at all. That is recorded rather than dropped -- a change
  /// nobody can be attributed to still belongs on the record -- so it needs a
  /// word here, and "someone" is the honest one.
  String nameOfActor(String? memberId) =>
      memberId == null ? 'Someone' : nameOf(memberId);

  /// Every member's name, for rendering the per-member lines of a diff.
  ///
  /// Past members included: an edit that changed what somebody owed is worth
  /// reading long after they have left the group.
  Map<String, String> get memberNames => {
    for (final member in [...members, ...pastMembers])
      member.id: nameOfMember(member),
  };

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
  final everyone = ref.watch(membersProvider(groupId)).value;
  final entryList = ref.watch(entriesProvider(groupId)).value;
  if (group == null || everyone == null || entryList == null) return null;

  final memberList = [
    for (final m in everyone)
      if (m.isActive) m,
  ];

  final accountId = ref.watch(currentAccountIdProvider);
  final profiles = ref.watch(profilesByIdProvider).value ?? const {};
  final balances = foldBalances(entryList);
  final broken = unbalancedEntries(entryList);

  return GroupLedger(
    group: group,
    members: memberList,
    pastMembers: [
      for (final m in everyone)
        if (!m.isActive) m,
    ],
    entries: entryList,
    balances: balances,
    transfers: group.simplifyDebts ? simplifyDebts(balances) : const [],
    me: memberList.where((m) => m.profileId == accountId).firstOrNull,
    profiles: profiles,
    brokenEntries: broken,
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

/// Reports the current session, and reconciles this device's identity with it.
///
/// It does NOT create one. Signing in anonymously the moment the app opened was
/// the app deciding who somebody was before asking, and it broke the arrival it
/// was meant to protect: a person who already had an account and tapped an
/// invite link had the slot claimed by a throwaway account and the single-use
/// token spent, with no way in afterwards. Every session now begins because
/// somebody chose Google, an email code, or [continueAsGuest].
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  Future<Account?> build() async {
    final auth = ref.watch(authServiceProvider);
    if (auth == null) return null;

    return auth.currentUser;
  }

  /// Being a guest, chosen rather than assumed.
  ///
  /// A real account with no credential attached: same uid, same rows, same
  /// row-level security as anybody else. What it does not have is any way back
  /// after losing the device, which is why it is offered as one of three
  /// choices instead of happening on its own.
  Future<Account> continueAsGuest() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      throw StateError('This build has no backend, so it has no accounts.');
    }

    final user = auth.currentUser ?? await auth.signInAnonymously();
    state = AsyncData(user);
    return user;
  }

  /// Ends the session.
  ///
  /// The local ledger is deleted rather than left behind. Keying the database
  /// by account already makes it unreachable to anybody else who signs in
  /// here — that is a correctness guarantee and it holds regardless — but a
  /// shared device is a privacy question as well as a correctness one, and
  /// "sign out" has to mean the next person cannot read what the last one
  /// spent. It costs a re-sync on return, which is the cheap half of the
  /// trade.
  Future<void> signOut() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    await forgetLocalLedger(ref.read(appDatabaseProvider));
    await auth.signOut();
    state = const AsyncData(null);
  }

  /// Deletes the account, then leaves the device as a sign-out would.
  ///
  /// The server call goes first and is not caught. If it fails there is nothing
  /// to clean up locally and the account still exists, so wiping the device
  /// would destroy the only copy of data the server still holds under an
  /// account the user believes is gone — the one outcome worse than the delete
  /// simply not working.
  ///
  /// It also has to happen while the session is still valid: the RPC is
  /// authorised by `auth.uid()`, so signing out first would leave nothing to
  /// identify the account by.
  Future<void> deleteAccount() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;

    await auth.deleteAccount();
    await forgetLocalLedger(ref.read(appDatabaseProvider));
    await auth.signOut();
    state = const AsyncData(null);
  }
}

/// Whether anybody is signed in, for the router to redirect on.
///
/// Separate from [sessionControllerProvider] because a redirect has to answer
/// synchronously: a router that waits on a future shows the wrong screen for a
/// frame, which on the web is a visible flash of the welcome page for someone
/// who is already signed in.
@Riverpod(keepAlive: true)
bool signedIn(Ref ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.value != null;
}

/// Runs sync and reports what happened.
///
/// Deliberately manual rather than a persistent realtime subscription: peak
/// concurrent realtime peers is what a hosted backend bills for, and pushing a
/// wake-up costs nothing. Live subscriptions are reserved for the rare case of
/// two people editing the same group at the same moment.
/// Runs sync on demand.
///
/// Holds no state, and that is deliberate rather than an omission. Nothing on
/// screen is driven by "how the last sync went": every panel is a query over
/// the local database, a pull that cannot reach the server changes nothing
/// visible, and a write the server refuses outright is surfaced by
/// [failedWritesProvider] instead — which outlives any one run, as it has to.
/// A [SyncReport] held here was read by nobody.
@riverpod
class SyncController extends _$SyncController {
  @override
  void build() {}

  /// Whether there is anything to sync to, and anybody to sync as.
  ///
  /// Syncing as nobody would have every request refused by RLS. That is the
  /// ordinary state before somebody has chosen an account, not an error, so it
  /// returns quietly.
  Future<SyncEngine?> _engine() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return null;
    if (await ref.read(sessionControllerProvider.future) == null) return null;
    return engine;
  }

  Future<void> syncGroup(String groupId) async {
    final engine = await _engine();
    await engine?.syncGroup(groupId);
  }

  /// Syncs every group this account belongs to, including ones this device has
  /// never seen.
  ///
  /// The list comes from the server, not from the local database. Sweeping
  /// local groups only is what made a second device — and a reinstall, and
  /// signing in after clearing browser data — show an empty app forever: the
  /// groups were on the server, readable, and nothing ever asked for them.
  ///
  /// The sweep itself belongs to [SyncEngine.syncEverything], which is the only
  /// place that can drain the outbox once and pull rates and profiles once for
  /// the whole run rather than per group.
  Future<void> syncAll() async {
    final engine = await _engine();
    await engine?.syncEverything();
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

/// Whether the device has a network, as it changes. See [NetworkSignal].
@Riverpod(keepAlive: true)
NetworkSignal networkSignal(Ref ref) => const NetworkSignal();

/// The thing that decides when a background sync is worth running.
///
/// keepAlive because it outlives every screen: it is started once by the app
/// shell and listens for the rest of the process. See [SyncScheduler] for what
/// the triggers are and why pull-to-refresh and push wakes deliberately do not
/// go through it.
@Riverpod(keepAlive: true)
SyncScheduler syncScheduler(Ref ref) {
  final scheduler = SyncScheduler(
    sync: () => ref.read(syncControllerProvider.notifier).syncAll(),
    online: ref.watch(networkSignalProvider).changes,
    // Every local write, from every screen, through one wire. See
    // [OutboxQueue.queued] for why this is not a sync call at each save site.
    writes: ref.watch(outboxQueueProvider).queued,
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
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
  Future<int> entriesLeftBehind() =>
      ref.read(entryRepositoryProvider).countLiveEntries();

  AuthService _auth() {
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      throw StateError('This build has no backend, so it has no accounts.');
    }
    return auth;
  }

  Future<EmailFlow> sendEmailCode(String email) async {
    // Deliberately does NOT establish a session first. With one, this attaches
    // the address and keeps every group on the device; without one, it is a
    // sign-in, or a sign-up for an address nobody has yet. Minting a guest
    // account here would put the caller in the first case when they asked for
    // the second, which is how somebody ends up owning an anonymous account
    // they never wanted.
    return _auth().sendEmailCode(email);
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
    await _settle();
    return outcome;
  }

  /// Throws [IdentityAlreadyInUse] unless [allowSignIn], so the screen gets a
  /// chance to say what signing in would cost before the session is replaced.
  Future<IdentityOutcome> continueWithGoogle({
    required String idToken,
    String? accessToken,
    bool allowSignIn = false,
  }) async {
    // No session established first, for the same reason as sendEmailCode.
    final outcome = await _auth().continueWithGoogle(
      idToken: idToken,
      accessToken: accessToken,
      allowSignIn: allowSignIn,
    );
    await _settle();
    return outcome;
  }

  /// Brings the device into line with whatever just happened to the session.
  ///
  /// Almost nothing, now. There is no ledger to wipe and no id to repoint:
  /// the database is named after the account, so invalidating the session is
  /// enough to close one account's file and open the other's. What is left is
  /// asking the server what this account has.
  Future<void> _settle() async {
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
    if (await ref.read(sessionControllerProvider.future) == null) return;
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
///
/// Watched, not counted once. The prompt sits on the group list, which is
/// mounted for as long as the app is open, so a one-shot count was taken on
/// the first frame and never taken again: the third expense of a session
/// arrived and nothing said anything until the next cold start.
@riverpod
Stream<int> totalEntryCount(Ref ref) =>
    ref.watch(entryRepositoryProvider).watchTotalCount();

/// What deleting this account would take with it, for the dialog that asks.
///
/// "You will lose your data" is ignorable. "The 2 groups only you have an
/// account in will be deleted" is not, and it is the half people get wrong —
/// the assumption is that leaving a shared group erases your side of it, when
/// in fact that side is your co-members' record too and stays exactly as it is.
@riverpod
Future<({int solo, int shared})> deletionImpact(Ref ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId == null) return (solo: 0, shared: 0);
  return ref.watch(groupRepositoryProvider).membershipBreakdown(accountId);
}

@Riverpod(keepAlive: true)
DriftCategoryRepository categoryRepository(Ref ref) =>
    DriftCategoryRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
DriftAnalyticsRepository analyticsRepository(Ref ref) =>
    DriftAnalyticsRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(entryRepositoryProvider),
    );

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
Stream<List<SpendBucket>> spendByCategory(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByCategory(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Stream<List<SpendBucket>> spendByMember(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByMember(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Stream<List<SpendBucket>> spendByMonth(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .spendByMonth(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Stream<List<Entry>> analyticsResults(Ref ref, String groupId) => ref
    .watch(analyticsRepositoryProvider)
    .search(ref.watch(analyticsFilterControllerProvider(groupId)));

@riverpod
Stream<List<String>> groupCurrencies(Ref ref, String groupId) =>
    ref.watch(analyticsRepositoryProvider).currenciesUsed(groupId);

/// Play's own update flow, and nothing anywhere else.
@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) => const AppUpdateService();

/// Asking for a store review, rarely and unconditionally.
@Riverpod(keepAlive: true)
ReviewPrompt reviewPrompt(Ref ref) =>
    ReviewPrompt(ref.watch(sharedPreferencesProvider));

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
      activity: ref.read(activityRepositoryProvider),
      myProfileId: ref.read(currentAccountIdProvider),
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
GoRouter router(Ref ref) {
  // A Listenable, not a watched value. `ref.watch(signedInProvider)` here would
  // rebuild this provider on every sign-in and hand MaterialApp.router a
  // brand new GoRouter — which discards the navigation stack and, because the
  // new router immediately re-evaluates its redirect, spins the tree. That is
  // exactly what GoRouter's refreshListenable exists to avoid: one router for
  // the life of the app, told when to reconsider.
  final signedIn = ValueNotifier(ref.read(signedInProvider));
  ref.onDispose(signedIn.dispose);
  ref.listen(signedInProvider, (_, next) => signedIn.value = next);

  return buildRouter(
    // Read through a callback rather than captured once: the router outlives
    // every session, and a bool frozen at construction would send a signed-in
    // user to the welcome screen forever.
    isSignedIn: () => ref.read(signedInProvider),
    refresh: signedIn,
  );
}

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
