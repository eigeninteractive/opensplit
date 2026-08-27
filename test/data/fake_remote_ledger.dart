import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/sync_cursor.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/member.dart';
import 'package:opensplit/domain/models/profile.dart';

/// An in-memory stand-in for the server.
///
/// It is deliberately faithful about the three things that actually determine
/// whether sync is correct, rather than being a convenient stub:
///
///  * it stamps `updated_at` from its own clock, never accepting the client's;
///  * it enforces `sum(payers) = sum(shares) = amount` and rejects anything
///    else, exactly as the deferred constraint trigger does;
///  * it can stamp a whole batch with one timestamp, because Postgres `now()`
///    is transaction time — which is what the composite cursor exists for.
///
/// Rows go through the same JSON codec the real adapter uses, so a field that
/// fails to survive the round trip fails here too.
class FakeRemoteLedger implements RemoteLedgerApi {
  FakeRemoteLedger({DateTime? start})
    : _now = start ?? DateTime.utc(2026, 8, 21, 12);

  final Map<String, Map<String, dynamic>> _entries = {};
  final Map<String, Map<String, dynamic>> _groups = {};
  final Map<String, Map<String, dynamic>> _members = {};

  /// Maps a client key to the entry id it created, making retries idempotent.
  final Map<String, String> _byClientKey = {};

  DateTime _now;

  /// When set, every write takes this timestamp instead of a fresh one.
  DateTime? _frozenAt;

  int upsertCalls = 0;

  /// Runs [body] with every write sharing a single timestamp, the way one
  /// Postgres transaction would.
  Future<T> inOneTransaction<T>(Future<T> Function() body) async {
    _frozenAt = _tick();
    try {
      return await body();
    } finally {
      _frozenAt = null;
    }
  }

  DateTime _tick() {
    _now = _now.add(const Duration(milliseconds: 1));
    return _now;
  }

  DateTime _stamp() => _frozenAt ?? _tick();

  /// The referential half of what the real server enforces.
  ///
  /// `members.group_id` and `entries.group_id` are real foreign keys, and both
  /// write policies additionally go through `is_group_member`/
  /// `is_group_creator`, neither of which can be true of a group the server has
  /// never seen. Both refusals are permanent — 23503 and 42501 are in
  /// SupabaseLedgerApi's permanent set — so a fake that accepted these would
  /// pass a push order the real server sends straight to the dead letters.
  void _assertGroupKnown(String groupId, String what) {
    if (_groups.containsKey(groupId)) return;
    throw RemoteRejected(
      '$what references group $groupId, which the server has never seen',
      permanent: true,
    );
  }

  /// The server-side invariant. The most valuable check in the system.
  void _assertBalanced(Entry entry) {
    final paid = entry.payers.fold(0, (sum, p) => sum + p.amountMinor);
    final owed = entry.shares.fold(0, (sum, s) => sum + s.amountMinor);
    if (paid != entry.amountMinor || owed != entry.amountMinor) {
      throw RemoteRejected(
        'Entry ${entry.id} does not balance: '
        'amount=${entry.amountMinor}, paid=$paid, owed=$owed',
        permanent: true,
      );
    }
  }

  @override
  Future<Entry> upsertEntry(Entry entry) async {
    upsertCalls++;
    _assertGroupKnown(entry.groupId, 'An expense');
    _assertBalanced(entry);

    // Idempotency on the client key: a retry after a dropped connection must
    // update the original row, never create a second one.
    final key = entry.clientKey;
    final existingId = key == null ? null : _byClientKey[key];
    final id = existingId ?? entry.id;
    if (key != null) _byClientKey[key] = id;

    final stored = entry.copyWith(id: id, updatedAt: _stamp());
    _entries[id] = entryToJson(stored);
    return entryFromJson(_entries[id]!);
  }

  @override
  Future<Entry> deleteEntry(String entryId) async {
    final json = _entries[entryId];
    if (json == null) {
      throw const RemoteRejected('No such entry', permanent: true);
    }
    final at = _stamp();
    json['deleted_at'] = at.toUtc().toIso8601String();
    json['updated_at'] = at.toUtc().toIso8601String();
    return entryFromJson(json);
  }

  @override
  Future<EntryDelta> pullEntries({
    required String groupId,
    SyncCursor? cursor,
    int limit = 200,
  }) async {
    final all =
        _entries.values
            .where((json) => json['group_id'] == groupId)
            .map(entryFromJson)
            .toList()
          ..sort((a, b) {
            final byTime = a.updatedAt.compareTo(b.updatedAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });

    final after = cursor == null
        ? all
        : all
              .where((e) => cursor.isBefore(SyncCursor(e.updatedAt, e.id)))
              .toList();

    final page = after.take(limit).toList();
    return EntryDelta(
      entries: page,
      nextCursor: page.isEmpty
          ? cursor
          : SyncCursor(page.last.updatedAt, page.last.id),
      hasMore: after.length > page.length,
    );
  }

  @override
  Future<Group?> pullGroup(String groupId) async {
    final json = _groups[groupId];
    return json == null ? null : groupFromJson(json);
  }

  @override
  Future<List<Member>> pullMembers(String groupId) async => [
    for (final json in _members.values)
      if (json['group_id'] == groupId) memberFromJson(json),
  ];

  /// Who the fake believes is holding the session.
  ///
  /// Set it to stand in for a device that has signed in and holds nothing
  /// locally — the case group discovery exists for.
  String? signedInProfileId;

  /// Redeems an invite, server-side: sets `profile_id` on a member row without
  /// any device having asked for it.
  ///
  /// The only way to reproduce the race the push path has to survive — a claim
  /// landing on the server while a device still believes the member is a
  /// placeholder.
  void claimMember(String memberId, String profileId) {
    final json = _members[memberId];
    if (json == null) throw StateError('No such member $memberId');
    json['profile_id'] = profileId;
    json['updated_at'] = _stamp().toIso8601String();
  }

  @override
  Future<List<String>> pullMyGroupIds() async {
    final uid = signedInProfileId;
    if (uid == null) return const [];
    return {
      for (final json in _members.values)
        if (json['profile_id'] == uid && json['left_at'] == null)
          json['group_id'] as String,
    }.toList()..sort();
  }

  @override
  Future<Group> pushGroup(Group group) async {
    // Stamped from the fake's own clock, exactly as Postgres does with now().
    // Accepting the client's value would let a test pass that a real server
    // would fail.
    final json = groupToJson(group)
      ..['updated_at'] = _stamp().toIso8601String();
    _groups[group.id] = json;
    return groupFromJson(json);
  }

  @override
  Future<Member> pushMember(Member member) async {
    // Merged over what is already stored, not substituted for it. PostgREST
    // builds an upsert's SET list from the keys actually present in the body,
    // so a column the client leaves out keeps its stored value — which is the
    // entire mechanism protecting a freshly claimed profile_id from a device
    // that has not pulled the claim yet. A fake that replaced the row wholesale
    // would pass a test the real server fails.
    _assertGroupKnown(member.groupId, 'A member');
    final json = {
      ...?_members[member.id],
      ...memberToJson(member),
      'updated_at': _stamp().toIso8601String(),
    };
    _members[member.id] = json;
    return memberFromJson(json);
  }

  /// Profiles, exactly as the server scopes them: your own plus your
  /// co-members'. The fake stores every one it is told about, and the tests
  /// that care about scoping use the real adapter.
  final Map<String, Map<String, dynamic>> _profiles = {};

  /// What the last profiles pull asked for, so a test can check the cursor is
  /// carried rather than every profile being refetched on every sync.
  DateTime? lastProfilesSince;

  @override
  Future<List<Profile>> pullProfiles({DateTime? since}) async {
    lastProfilesSince = since;
    final rows =
        _profiles.values
            .where(
              (json) =>
                  since == null ||
                  DateTime.parse(json['updated_at'] as String).isAfter(since),
            )
            .toList()
          ..sort(
            (a, b) => (a['updated_at'] as String).compareTo(
              b['updated_at'] as String,
            ),
          );
    return [for (final row in rows) profileFromJson(row)];
  }

  @override
  Future<Profile> pushProfile(Profile profile) async {
    final json = {
      ...?_profiles[profile.id],
      ...profileToJson(profile),
      'updated_at': _stamp().toIso8601String(),
    };
    _profiles[profile.id] = json;
    return profileFromJson(json);
  }

  /// The activity feed, appended to by whichever device made the change.
  final List<EntryEvent> _events = [];

  /// Sorted, because the real feed is ordered by `created_at` and the pull
  /// cursor takes the last row it is given as the new high-water mark. A fake
  /// that answered in insertion order would let a test pass against an
  /// ordering the server never produces.
  @override
  Future<List<EntryEvent>> pullEntryEvents({
    required String groupId,
    DateTime? since,
  }) async =>
      [
        for (final event in _events)
          if (event.groupId == groupId &&
              (since == null || event.createdAt.isAfter(since)))
            event,
      ]..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

  @override
  Future<EntryEvent> pushEntryEvent(EntryEvent event) async {
    _assertGroupKnown(event.groupId, 'an activity event');
    if (!_entries.containsKey(event.entryId)) {
      throw RemoteRejected(
        'entry_events references an entry the server does not have',
        permanent: true,
      );
    }
    // Append-only and idempotent on the id, exactly as the real table is: the
    // client chooses the id, so a retry is provably the same row rather than a
    // second copy of it.
    final existing = _events.where((e) => e.id == event.id).firstOrNull;
    if (existing != null) return existing;

    // The clock is the server's, like `clock_timestamp()` on the real table.
    // Stamping it here rather than trusting the one that arrived is what the
    // activity cursor depends on, so the fake has to do it too or a test would
    // pass against a guarantee the server is the only thing actually making.
    final stored = event.copyWith(createdAt: _stamp());
    _events.add(stored);
    return stored;
  }

  /// Records an event that arrived from somebody else's device.
  void seedEvent(EntryEvent event) => _events.add(event);

  /// Puts a profile on the server without going through a push, for arranging
  /// "somebody else renamed themselves" in a test.
  void seedProfile(Profile profile) {
    _profiles[profile.id] = {
      ...profileToJson(profile),
      'updated_at': _stamp().toIso8601String(),
    };
  }

  /// Published rates, keyed by "date|currency", exactly as the server holds
  /// them: against USD, immutable once published.
  final Map<String, RemoteFxRate> _fxRates = {};

  /// Records rates as the server's fetch-fx function would.
  void publishFxRate({
    required String asOf,
    required String currency,
    required double rate,
    String source = 'fake',
  }) {
    _fxRates['$asOf|$currency'] = RemoteFxRate(
      asOf: asOf,
      currency: currency,
      rate: rate,
      source: source,
    );
  }

  /// How many times a client has asked for rates. Lets a test prove the
  /// high-water mark actually stops the traffic.
  int fxPulls = 0;

  /// Simulates the rate endpoint being unavailable.
  bool failFxPulls = false;

  @override
  Future<List<RemoteFxRate>> pullFxRates({required String since}) async {
    fxPulls++;
    if (failFxPulls) throw StateError('rates unavailable');
    return [
      for (final rate in _fxRates.values)
        if (rate.asOf.compareTo(since) >= 0) rate,
    ]..sort((a, b) => a.asOf.compareTo(b.asOf));
  }

  /// What a client has asked the server to backfill.
  final List<({DateTime asOf, String currency})> fxBackfillRequests = [];

  @override
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  }) async {
    fxBackfillRequests.add((asOf: asOf, currency: currency));
  }

  int get entryCount => _entries.length;
}
