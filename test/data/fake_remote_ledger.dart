import 'package:opensplit/data/sync/change_feed.dart';
import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/sync_cursor.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/domain/activity/snapshot_diff.dart';
import 'package:opensplit/domain/models/entry_snapshot.dart';
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
  int pullMyGroupIdsCalls = 0;

  /// Test hook for proving that two sync engines never overlap discovery.
  Future<void> Function(int call)? beforePullMyGroupIds;

  /// Pauses an upload after the client captured its local revision.
  Future<void> Function(Entry entry)? beforeUpsertEntry;

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
      kind: RejectionKind.permanent,
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
        kind: RejectionKind.permanent,
      );
    }
  }

  /// What an expense currently says about money, in a form two of them can be
  /// compared in. Amounts only: a weight is how a split was expressed, the
  /// amounts are what anybody owes.
  static String _moneyOf(Entry entry) => [
    entry.amountMinor,
    for (final payer in [
      ...entry.payers,
    ]..sort((a, b) => a.memberId.compareTo(b.memberId)))
      'p:${payer.memberId}=${payer.amountMinor}',
    for (final share in [
      ...entry.shares,
    ]..sort((a, b) => a.memberId.compareTo(b.memberId)))
      's:${share.memberId}=${share.amountMinor}',
  ].join('|');

  /// The base-version check, exactly as `upsert_entry` applies it.
  ///
  /// Refuses only when the base has moved *and* applying the write would move
  /// money away from where the server has it. A fake that refused on a stale
  /// base alone would pass a test the real server fails -- and one that never
  /// refused would let the whole conflict path go untested.
  void _assertNotStale(Entry entry, DateTime? baseUpdatedAt) {
    if (baseUpdatedAt == null) return;
    final json = _entries[entry.id];
    if (json == null) return;

    final stored = entryFromJson(json);
    if (stored.updatedAt == baseUpdatedAt) return;
    if (_moneyOf(stored) == _moneyOf(entry)) return;

    throw RemoteRejected(
      'Entry ${entry.id} changed since this edit was composed',
      kind: RejectionKind.stale,
    );
  }

  @override
  Future<Entry> upsertEntry(Entry entry, {DateTime? baseUpdatedAt}) async {
    upsertCalls++;
    await beforeUpsertEntry?.call(entry);
    _assertGroupKnown(entry.groupId, 'An expense');
    _assertBalanced(entry);
    _assertNotStale(entry, baseUpdatedAt);

    // Idempotency on the client key: a retry after a dropped connection must
    // update the original row, never create a second one.
    final key = entry.clientKey;
    final existingId = key == null ? null : _byClientKey[key];
    final id = existingId ?? entry.id;
    if (key != null) _byClientKey[key] = id;

    final stored = entry.copyWith(id: id, updatedAt: _stamp());
    _entries[id] = entryToJson(stored);
    _recordSnapshot(stored);
    return entryFromJson(_entries[id]!);
  }

  @override
  Future<Entry> deleteEntry(
    String entryId, {
    required DateTime baseUpdatedAt,
  }) async {
    final json = _entries[entryId];
    if (json == null) {
      throw const RemoteRejected(
        'No such entry',
        kind: RejectionKind.permanent,
      );
    }
    final current = entryFromJson(json);
    if (current.isDeleted) return current;
    if (current.updatedAt != baseUpdatedAt) {
      throw RemoteRejected(
        'Entry $entryId changed since this deletion was composed',
        kind: RejectionKind.stale,
      );
    }

    final at = _stamp();
    json['deleted_at'] = at.toUtc().toIso8601String();
    json['updated_at'] = at.toUtc().toIso8601String();
    final stored = entryFromJson(json);
    _recordSnapshot(stored);
    return stored;
  }

  @override
  Future<ChangePage<Entry>> pullEntries({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) async => _page(
    rows: [
      for (final json in _entries.values)
        if (json['group_id'] == groupId)
          (cursor: _cursorOf(json, 'updated_at'), row: entryFromJson(json)),
    ],
    since: since,
    limit: limit,
  );

  /// One keyset page, exactly as the real adapter answers.
  ///
  /// Faithful about paging rather than returning everything at once, because
  /// [SyncEngine.drain]'s loop is the thing under test: a fake that always
  /// answered in full would never once exercise the cursor advancing across a
  /// page boundary, which is where every paging bug this project has had lived.
  ChangePage<T> _page<T>({
    required Iterable<({SyncCursor cursor, T row})> rows,
    required SyncCursor? since,
    required int limit,
  }) {
    final matching =
        rows
            .where((row) => since == null || since.isBefore(row.cursor))
            .toList()
          ..sort((a, b) => a.cursor.compareTo(b.cursor));

    final page = matching.take(limit).toList();
    return ChangePage(
      rows: [for (final row in page) row.row],
      cursor: page.isEmpty ? null : page.last.cursor,
      hasMore: matching.length > limit,
    );
  }

  static SyncCursor _cursorOf(Map<String, dynamic> json, String timeColumn) =>
      SyncCursor(
        DateTime.parse(json[timeColumn] as String),
        json['id'] as String,
      );

  @override
  Future<ChangePage<Group>> pullGroup({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) async => _page(
    rows: [
      for (final json in _groups.values)
        if (json['id'] == groupId)
          (cursor: _cursorOf(json, 'updated_at'), row: groupFromJson(json)),
    ],
    since: since,
    limit: limit,
  );

  @override
  Future<ChangePage<Member>> pullMembers({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) async => _page(
    rows: [
      for (final json in _members.values)
        if (json['group_id'] == groupId)
          (cursor: _cursorOf(json, 'updated_at'), row: memberFromJson(json)),
    ],
    since: since,
    limit: limit,
  );

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
    pullMyGroupIdsCalls++;
    await beforePullMyGroupIds?.call(pullMyGroupIdsCalls);
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
  SyncCursor? lastProfilesSince;

  @override
  Future<ChangePage<Profile>> pullProfiles({
    SyncCursor? since,
    required int limit,
  }) async {
    lastProfilesSince = since;
    return _page(
      rows: [
        for (final json in _profiles.values)
          (cursor: _cursorOf(json, 'updated_at'), row: profileFromJson(json)),
      ],
      since: since,
      limit: limit,
    );
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

  /// The activity log, written here and nowhere else.
  ///
  /// The real table has no insert, update or delete grant for any client; a
  /// deferred constraint trigger is its only writer. So the fake writes these
  /// rows itself, from the expense it just committed, and offers no way at all
  /// to hand one in. A fake that accepted a client-authored line would let a
  /// test pass against the exact thing the redesign removed.
  final List<EntrySnapshot> _snapshots = [];

  var _snapshotSeq = 0;

  /// Who the fake takes the current request to be from.
  ///
  /// Stands in for `auth.uid()`, which is what `snapshot_entry` resolves the
  /// actor through. Authorship is therefore decided here, from the session, and
  /// is not something a caller can supply -- which is the property being
  /// modelled.
  String? actingProfileId;

  /// Records what an expense now looks like, exactly as `snapshot_entry` does.
  void _recordSnapshot(Entry entry) {
    final actor = _members.values
        .where(
          (m) =>
              m['group_id'] == entry.groupId &&
              m['profile_id'] == actingProfileId &&
              m['left_at'] == null,
        )
        .map((m) => m['id'] as String)
        .firstOrNull;

    final taken = EntrySnapshot(
      id: 'snapshot-${_snapshotSeq++}',
      entryId: entry.id,
      groupId: entry.groupId,
      actorId: actor,
      createdAt: _stamp(),
      description: entry.description,
      currency: entry.currency,
      amountMinor: entry.amountMinor,
      entryDate: entry.entryDate,
      splitKind: entry.splitKind,
      categoryId: entry.categoryId,
      notes: entry.notes,
      deletedAt: entry.deletedAt,
      payers: [
        for (final payer in entry.payers)
          MemberAmount(
            memberId: payer.memberId,
            amountMinor: payer.amountMinor,
          ),
      ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
      shares: [
        for (final share in entry.shares)
          MemberAmount(
            memberId: share.memberId,
            amountMinor: share.amountMinor,
          ),
      ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
    );

    // The same dedup the trigger applies: a re-saved editor and a retried sync
    // record nothing, so one edit is one line however many times it arrives.
    final latest = _snapshots
        .where((snapshot) => snapshot.entryId == entry.id)
        .lastOrNull;
    if (latest != null && recordsSameShape(latest, taken)) return;

    _snapshots.add(taken);
  }

  @override
  Future<ChangePage<EntrySnapshot>> pullEntrySnapshots({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) async => _page(
    rows: [
      for (final snapshot in _snapshots)
        if (snapshot.groupId == groupId)
          (cursor: SyncCursor(snapshot.createdAt, snapshot.id), row: snapshot),
    ],
    since: since,
    limit: limit,
  );

  /// Records history that arrived from somebody else's device.
  void seedSnapshot(EntrySnapshot snapshot) => _snapshots.add(snapshot);

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
