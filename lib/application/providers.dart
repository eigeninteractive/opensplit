import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../data/repositories/drift_currency_repository.dart';
import '../data/repositories/drift_entry_repository.dart';
import '../data/repositories/drift_group_repository.dart';
import '../data/repositories/drift_profile_repository.dart';
import '../domain/balance/balance_fold.dart';
import '../domain/balance/member_balance.dart';
import '../domain/balance/simplify.dart';
import '../domain/models/currency.dart';
import '../domain/models/entry.dart';
import '../domain/models/group.dart';
import '../domain/models/member.dart';
import '../domain/models/profile.dart';
import '../domain/repositories/currency_repository.dart';
import '../domain/repositories/entry_repository.dart';
import '../domain/repositories/group_repository.dart';
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

@Riverpod(keepAlive: true)
GroupRepository groupRepository(Ref ref) =>
    DriftGroupRepository(ref.watch(appDatabaseProvider));

@Riverpod(keepAlive: true)
EntryRepository entryRepository(Ref ref) =>
    DriftEntryRepository(ref.watch(appDatabaseProvider));

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
