import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/domain/models/category.dart';
import 'package:opensplit/domain/models/currency.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/group.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/models/member.dart';
import 'package:opensplit/domain/models/profile.dart';

import 'server_reference_data.dart';

/// An in-memory stand-in for one group's Durable Object, per group.
///
/// Deliberately faithful about the things that actually decide whether sync is
/// correct, rather than being a convenient stub:
///
///  * every committed change takes the next sequence number, and the client
///    can never invent one;
///  * one number per change, not per row, so an expense and its snapshot share
///    it and a page can never be cut between them;
///  * it enforces `sum(payers) = sum(shares) = amount`;
///  * a stale base is refused only when applying the write would move money.
///
/// It is much shorter than the fake it replaced, and the missing parts are the
/// interesting bit. That one had to model Postgres transaction time — a whole
/// `inOneTransaction` hook existed so a batch could share an `updated_at`,
/// because the composite `(timestamp, id)` cursor existed to survive exactly
/// that. There is no such thing to model here.
class FakeRemoteLedger implements RemoteLedgerApi {
  FakeRemoteLedger({DateTime? start})
    : _now = start ?? DateTime.utc(2026, 8, 21, 12);

  final Map<String, _FakeGroup> _groups = {};
  DateTime _now;

  int upsertCalls = 0;
  int bootstrapCalls = 0;

  /// Test hook for proving that two sync engines never overlap discovery.
  Future<void> Function(int call)? beforeBootstrap;

  /// Pauses an upload after the client captured its local revision.
  Future<void> Function(Entry entry)? beforeUpsertEntry;

  /// The account this fake answers as. Groups it is not a member of are
  /// refused, and are not listed by [bootstrap].
  String profileId = 'profile-1';

  DateTime _tick() => _now = _now.add(const Duration(milliseconds: 1));

  _FakeGroup _group(String groupId) {
    final group = _groups[groupId];
    if (group == null) {
      throw const RemoteRejected(
        'No such group.',
        kind: RejectionKind.permanent,
        code: 'no_group',
      );
    }
    return group;
  }

  /// Seeds a group as though it had been created and synced already.
  ///
  /// Takes the same path a real create does, so a test cannot set up a state
  /// the app could not have reached.
  Future<Group> seedGroup(Group group, {required Member creator}) =>
      createGroup(group, creator: creator);

  @override
  Future<RemoteBootstrap> bootstrap() async {
    bootstrapCalls++;
    await beforeBootstrap?.call(bootstrapCalls);

    return RemoteBootstrap(
      profileId: profileId,
      displayName: 'Ravi',
      upiVpa: null,
      isAnonymous: false,
      groupIds: [
        for (final group in _groups.values)
          if (group.members.values.any(
            (member) => member.profileId == profileId && member.leftAt == null,
          ))
            group.id,
      ]..sort(),
    );
  }

  @override
  Future<GroupChanges> pullChanges({
    required String groupId,
    required int since,
    required int limit,
  }) async {
    final group = _group(groupId);

    // Sequence numbers strictly after the cursor, one page's worth, never cut
    // inside a number.
    final moved = <int>{
      if (group.meta.seq! > since) group.meta.seq!,
      for (final member in group.members.values)
        if (member.seq! > since) member.seq!,
      for (final entry in group.entries.values)
        if (entry.seq! > since) entry.seq!,
      for (final event in group.events)
        if (event.seq! > since) event.seq!,
    }.toList()..sort();

    if (moved.isEmpty) {
      return GroupChanges(
        groupId: groupId,
        seq: since,
        hasMore: false,
        purgedAt: null,
        group: null,
        members: const [],
        entries: const [],
        events: const [],
      );
    }

    final hasMore = moved.length > limit;
    final upTo = hasMore ? moved[limit - 1] : moved.last;
    bool inWindow(int? seq) => seq != null && seq > since && seq <= upTo;

    return GroupChanges(
      groupId: groupId,
      seq: upTo,
      hasMore: hasMore,
      purgedAt: null,
      group: inWindow(group.meta.seq) ? group.meta : null,
      members: [
        for (final member in group.members.values)
          if (inWindow(member.seq)) member,
      ]..sort((a, b) => a.seq!.compareTo(b.seq!)),
      entries: [
        for (final entry in group.entries.values)
          if (inWindow(entry.seq)) entry,
      ]..sort((a, b) => a.seq!.compareTo(b.seq!)),
      events:
          [
            for (final event in group.events)
              if (inWindow(event.seq)) event,
          ]..sort((a, b) {
            final bySeq = a.seq!.compareTo(b.seq!);
            return bySeq != 0 ? bySeq : a.ordinal!.compareTo(b.ordinal!);
          }),
    );
  }

  @override
  Future<Entry> pushEntry(Entry entry) async {
    upsertCalls++;
    await beforeUpsertEntry?.call(entry);

    final group = _group(entry.groupId);
    _assertBalanced(entry);

    // A retry that re-minted the id. Answering with the expense already
    // recorded is the whole point of the key existing.
    final key = entry.clientKey;
    if (key != null && !group.entries.containsKey(entry.id)) {
      final existing = group.byClientKey[key];
      if (existing != null) return group.entries[existing]!;
    }

    final stored = group.entries[entry.id];
    if (stored != null) {
      _assertBaseIsCurrent(stored, entry);
      if (!_differs(stored, entry)) return stored;
    }

    final seq = group.nextSeq();
    final written = entry.copyWith(
      seq: seq,
      createdBy: stored?.createdBy ?? entry.createdBy,
      createdAt: stored?.createdAt ?? entry.createdAt,
      clientKey: stored?.clientKey ?? entry.clientKey,
      // An edit never resurrects a deleted expense. That is `restoreEntry`.
      deletedAt: stored?.deletedAt,
    );

    group.entries[entry.id] = written;
    if (key != null) group.byClientKey[key] = entry.id;
    group.snapshot(written, seq, _tick());
    return written;
  }

  @override
  Future<Entry> deleteEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  }) => _setDeleted(groupId, entryId, baseSeq, deleted: true);

  @override
  Future<Entry> restoreEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  }) => _setDeleted(groupId, entryId, baseSeq, deleted: false);

  Future<Entry> _setDeleted(
    String groupId,
    String entryId,
    int baseSeq, {
    required bool deleted,
  }) async {
    final group = _group(groupId);
    final stored = group.entries[entryId];
    if (stored == null) {
      throw const RemoteRejected(
        'No such expense.',
        kind: RejectionKind.permanent,
        code: 'no_such_entry',
      );
    }

    // A retry after the server committed but before its answer arrived.
    if (stored.isDeleted == deleted) return stored;

    // Deleting always moves money, so it must carry the exact version the
    // device last saw.
    if (stored.seq != baseSeq) {
      throw const RemoteRejected(
        'This expense changed since you opened it.',
        kind: RejectionKind.stale,
        code: 'stale_base',
      );
    }

    final seq = group.nextSeq();
    final written = stored.copyWith(
      deletedAt: deleted ? _tick() : null,
      seq: seq,
    );
    group.entries[entryId] = written;
    group.snapshot(written, seq, _tick());
    return written;
  }

  @override
  Future<Group> createGroup(Group group, {required Member creator}) async {
    final existing = _groups[group.id];
    if (existing != null) return existing.meta;

    final fake = _FakeGroup(group.id);
    _groups[group.id] = fake;

    final seq = fake.nextSeq();
    fake.meta = group.copyWith(seq: seq, createdBy: creator.id);
    fake.members[creator.id] = creator.copyWith(
      seq: seq,
      profileId: creator.profileId ?? profileId,
    );
    return fake.meta;
  }

  @override
  Future<Group> updateGroup(Group group) async {
    final fake = _group(group.id);
    final seq = fake.nextSeq();
    fake.meta = fake.meta.copyWith(
      name: group.name,
      simplifyDebts: group.simplifyDebts,
      archivedAt: group.archivedAt,
      seq: seq,
    );
    return fake.meta;
  }

  @override
  Future<Member> addMember(Member member) async {
    final fake = _group(member.groupId);
    final seq = fake.nextSeq();
    final written = member.copyWith(seq: seq, profileId: null);
    fake.members[member.id] = written;
    return written;
  }

  @override
  Future<Member> updateMember(Member member) async {
    final fake = _group(member.groupId);
    final stored = fake.members[member.id];
    if (stored == null) {
      throw const RemoteRejected(
        'No such member in this group.',
        kind: RejectionKind.permanent,
        code: 'no_such_member',
      );
    }

    final seq = fake.nextSeq();
    final written = stored.copyWith(
      displayName: member.displayName,
      upiVpa: member.upiVpa,
      leftAt: member.leftAt,
      seq: seq,
    );
    fake.members[member.id] = written;
    return written;
  }

  // ----------------------------------------------------------- test fixtures

  /// Adds a placeholder to a seeded group without going through the outbox.
  Member seedMember(Member member) {
    final group = _group(member.groupId);
    final written = member.copyWith(seq: group.nextSeq());
    group.members[member.id] = written;
    return written;
  }

  /// Somebody claims a placeholder, which sets exactly one column.
  Member claimMember(String groupId, String memberId, String claimant) {
    final group = _group(groupId);
    final written = group.members[memberId]!.copyWith(
      profileId: claimant,
      seq: group.nextSeq(),
    );
    group.members[memberId] = written;
    return written;
  }

  /// The server's own view of one member, read without syncing.
  ///
  /// The only way to ask what actually landed. A test that checks this by
  /// pulling it back onto a device is really testing the device's merge rules,
  /// which is a different question and the one it was trying to control for.
  Member memberOn(String groupId, String memberId) =>
      _group(groupId).members[memberId]!;

  /// An expense written by somebody else, as it would arrive from the server.
  Entry seedEntry(Entry entry) {
    final group = _group(entry.groupId);
    final seq = group.nextSeq();
    final written = entry.copyWith(seq: seq);
    group.entries[entry.id] = written;
    group.snapshot(written, seq, _tick());
    return written;
  }

  int entryCount(String groupId) => _group(groupId).entries.length;

  int seqOf(String groupId) => _group(groupId)._seq;

  /// Writes a profile as the account itself would, stamping it now.
  ///
  /// The stamp is the feed's cursor, so seeding two profiles in a row makes
  /// the second strictly newer -- which is what lets a test put a row behind
  /// the cursor on purpose.
  void seedProfile(Profile profile) =>
      profiles[profile.id] = profile.copyWith(updatedAt: _tick());

  void publishFxRate({
    required String asOf,
    required String currency,
    required double rate,
    String source = 'test',
  }) => _rates.add(
    RemoteFxRate(asOf: asOf, currency: currency, rate: rate, source: source),
  );

  /// When set, every rate pull is refused. A missing rate costs an estimate,
  /// never a balance, so a sync carrying money must survive one.
  bool failFxPulls = false;
  int fxPulls = 0;
  String? lastFxSince;

  // -------------------------------------------------- phases 4 and 5

  final Map<String, Profile> profiles = {};
  final List<RemoteFxRate> _rates = [];

  /// What the last profile pull asked for, which is how a test sees the cursor.
  DateTime? lastProfilesSince;

  /// The one feed still paged on `(updatedAt, id)`, and faithfully so.
  ///
  /// Profiles live in D1, which several requests write at once, so there is
  /// nothing there that can hand out a sequence number. The tie-break is
  /// therefore real and is modelled: rows sharing an instant are ordered by id
  /// and resumed by the pair, because a cursor on the timestamp alone skips
  /// the rest of such a batch forever or re-reads it forever.
  @override
  Future<ProfilePage> pullProfiles({
    DateTime? since,
    String? sinceId,
    required int limit,
  }) async {
    lastProfilesSince = since;

    final ordered = profiles.values.toList()
      ..sort((x, y) {
        final byTime = (x.updatedAt ?? _epoch).compareTo(y.updatedAt ?? _epoch);
        return byTime != 0 ? byTime : x.id.compareTo(y.id);
      });

    final after = [
      for (final profile in ordered)
        if (since == null ||
            (profile.updatedAt ?? _epoch).isAfter(since) ||
            ((profile.updatedAt ?? _epoch) == since &&
                (sinceId == null || profile.id.compareTo(sinceId) > 0)))
          profile,
    ];

    final page = after.take(limit).toList();
    if (page.isEmpty) return const ProfilePage.empty();

    return ProfilePage(
      rows: page,
      cursor: page.last.updatedAt,
      cursorId: page.last.id,
      hasMore: after.length > limit,
    );
  }

  static final _epoch = DateTime.utc(1970);

  @override
  Future<List<Profile>> pullProfilesByIds(List<String> ids) async => [
    for (final id in ids) ?profiles[id],
  ];

  @override
  Future<Profile> pushProfile(Profile profile) async {
    final written = profile.copyWith(updatedAt: _tick());
    profiles[profile.id] = written;
    return written;
  }

  /// What the server holds, mutable so a test can add, withdraw or rename one.
  ///
  /// The device ships a seed list, so proving that this feed does anything at
  /// all means making the server disagree with it.
  late final List<Currency> serverCurrencies = [
    for (final row in defaultCurrencies)
      Currency(
        code: row.code,
        exponent: row.exponent,
        symbol: row.symbol,
        name: row.name,
      ),
  ];

  @override
  Future<List<Currency>> pullCurrencies() async => List.of(serverCurrencies);

  @override
  Future<List<Category>> pullCategories() async => [
    for (final row in defaultCategories)
      Category(id: row.id, name: row.name, icon: row.icon),
  ];

  @override
  Future<List<RemoteFxRate>> pullFxRates({required String since}) async {
    fxPulls++;
    lastFxSince = since;
    if (failFxPulls) {
      throw const RemoteRejected(
        'Rates are unavailable.',
        kind: RejectionKind.transient,
      );
    }
    return [
      for (final rate in _rates)
        if (rate.asOf.compareTo(since) >= 0) rate,
    ];
  }

  @override
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  }) async {}

  // --------------------------------------------------------------- the rules

  static void _assertBalanced(Entry entry) {
    if (entry.isBalanced) return;
    throw const RemoteRejected(
      'This expense does not add up.',
      kind: RejectionKind.permanent,
      code: 'unbalanced',
    );
  }

  /// A stale base is refused only when applying the write would move money.
  ///
  /// Two people fixing a typo do not arbitrate; an edit carrying a stale
  /// amount does.
  static void _assertBaseIsCurrent(Entry stored, Entry incoming) {
    if (incoming.seq == null || stored.seq == incoming.seq) return;
    if (_money(stored) == _money(incoming)) return;

    throw const RemoteRejected(
      'This expense changed since you opened it.',
      kind: RejectionKind.stale,
      code: 'stale_base',
    );
  }

  static String _money(Entry entry) {
    final payers = [
      for (final payer in entry.payers)
        '${payer.memberId}:${payer.amountMinor}',
    ]..sort();
    final shares = [
      for (final share in entry.shares)
        '${share.memberId}:${share.amountMinor}',
    ]..sort();
    return '${entry.amountMinor}|$payers|$shares';
  }

  /// A push that changes nothing spends no sequence number, so a retried
  /// outbox item does not re-notify every device in the group.
  static bool _differs(Entry stored, Entry incoming) =>
      _money(stored) != _money(incoming) ||
      stored.description != incoming.description ||
      stored.categoryId != incoming.categoryId ||
      stored.currency != incoming.currency ||
      stored.entryDate != incoming.entryDate ||
      stored.splitKind != incoming.splitKind ||
      stored.kind != incoming.kind ||
      stored.notes != incoming.notes;
}

class _FakeGroup {
  _FakeGroup(this.id);

  final String id;
  late Group meta;

  final Map<String, Member> members = {};
  final Map<String, Entry> entries = {};
  final Map<String, String> byClientKey = {};
  final List<GroupEventRow> events = [];

  int _seq = 0;
  int nextSeq() => ++_seq;

  /// The record, written by the thing that committed the change.
  ///
  /// Deduped the same way the real object dedupes: a snapshot byte-identical
  /// to the previous one appends nothing, so a re-saved editor produces no
  /// "somebody edited nothing" line.
  void snapshot(Entry entry, int seq, DateTime at) {
    final payload = <String, Object?>{
      'kind': entry.kind.name,
      'description': entry.description,
      'currency': entry.currency,
      'amountMinor': entry.amountMinor,
      'entryDate': entry.entryDate.toIso8601String().substring(0, 10),
      'splitKind': entry.splitKind.name,
      'categoryId': entry.categoryId,
      'notes': entry.notes,
      'deletedAt': entry.deletedAt?.toIso8601String(),
      'payers': [
        for (final payer in [
          ...entry.payers,
        ]..sort((a, b) => a.memberId.compareTo(b.memberId)))
          {'memberId': payer.memberId, 'amountMinor': payer.amountMinor},
      ],
      'shares': [
        for (final share in [
          ...entry.shares,
        ]..sort((a, b) => a.memberId.compareTo(b.memberId)))
          {'memberId': share.memberId, 'amountMinor': share.amountMinor},
      ],
    };

    final previous = events.lastWhere(
      (event) =>
          event.subjectId == entry.id && event.kind == GroupEventKind.entry,
      orElse: () => _absent,
    );
    if (previous != _absent && '${previous.payload}' == '$payload') return;

    events.add(
      GroupEventRow(
        id: 'event-${events.length + 1}',
        groupId: id,
        actorId: entry.createdBy,
        createdAt: at,
        kind: GroupEventKind.entry,
        subjectId: entry.id,
        payload: payload,
        seq: seq,
        ordinal: events.where((event) => event.seq == seq).length,
      ),
    );
  }

  static final _absent = GroupEventRow(
    id: '',
    groupId: '',
    actorId: null,
    createdAt: DateTime.utc(1970),
    kind: GroupEventKind.entry,
    subjectId: null,
    payload: const {},
  );
}
