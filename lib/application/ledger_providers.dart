import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/balance/balance_fold.dart';
import '../domain/balance/member_balance.dart';
import '../domain/balance/simplify.dart';
import '../domain/fx/estimated_total.dart';
import '../domain/member_identity.dart';
import '../domain/models/category.dart';
import '../domain/models/currency.dart';
import '../domain/models/entry.dart';
import '../domain/models/group.dart';
import '../domain/models/group_event.dart';
import '../domain/models/member.dart';
import '../domain/models/profile.dart';
import '../domain/analytics/analytics_query.dart';
import 'local_providers.dart';

part 'ledger_providers.g.dart';

/// A group's activity feed, newest first.
@riverpod
Stream<List<GroupEvent>> groupActivity(Ref ref, String groupId) =>
    ref.watch(activityRepositoryProvider).watchGroup(groupId);

/// One expense's history, in the order it happened.
@riverpod
Stream<List<GroupEvent>> entryActivity(Ref ref, String entryId) =>
    ref.watch(activityRepositoryProvider).watchEntry(entryId);

@riverpod
Stream<Map<String, Profile>> profilesById(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchAll();

/// The stored profile for a member, when they have an account.
@riverpod
Stream<Profile?> profile(Ref ref, String? profileId) => profileId == null
    ? Stream.value(null)
    : ref.watch(profileRepositoryProvider).watch(profileId);

/// This account's own name and payment handle.
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
  Future<void> save({required String displayName, String? upiVpa}) async {
    final accountId = ref.read(currentAccountIdProvider);
    if (accountId == null) return;

    final profiles = ref.read(profileRepositoryProvider);
    final handle = upiVpa?.trim();

    await profiles.upsert(
      Profile(
        id: accountId,
        displayName: displayName.trim(),
        upiVpa: handle == null || handle.isEmpty ? null : handle,
      ),
    );
  }
}

/// Currencies, keyed by code.
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
@riverpod
Stream<List<Member>> members(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchMembers(groupId, includeLeft: true);

@riverpod
Stream<List<Entry>> entries(Ref ref, String groupId) =>
    ref.watch(entryRepositoryProvider).watchEntries(groupId);

/// Everything a group screen needs, folded once.
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
  final List<Entry> brokenEntries;

  /// Whether the balances on this ledger can be trusted to add up.
  bool get isCoherent => brokenEntries.isEmpty;

  /// What to call [member], and where to pay them.
  String nameOfMember(Member member) =>
      memberDisplayName(member, profiles[member.profileId]);

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
  bool isSettledUp(String memberId) =>
      !balances.any((balance) => balance.memberId == memberId);

  String nameOf(String memberId) {
    final member = memberById(memberId);
    return member == null ? '—' : nameOfMember(member);
  }

  /// What to print against a change in the activity feed.
  String nameOfActor(String? memberId) =>
      memberId == null ? 'Someone' : nameOf(memberId);

  /// Every member's name, for rendering the per-member lines of a diff.
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

/// How many entries this device has recorded, across every group.
@riverpod
Stream<int> totalEntryCount(Ref ref) =>
    ref.watch(entryRepositoryProvider).watchTotalCount();

/// What deleting this account would take with it, for the dialog that asks.
@riverpod
Future<({int solo, int shared})> deletionImpact(Ref ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId == null) return (solo: 0, shared: 0);
  return ref.watch(groupRepositoryProvider).membershipBreakdown(accountId);
}

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
