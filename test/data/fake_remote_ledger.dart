import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/data/sync/sync_cursor.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/domain/models/member.dart';

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
    final json = memberToJson(member)
      ..['updated_at'] = _stamp().toIso8601String();
    _members[member.id] = json;
    return memberFromJson(json);
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

  int get entryCount => _entries.length;
}
