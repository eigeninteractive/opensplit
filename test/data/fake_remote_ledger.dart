import 'package:drift/drift.dart' show Value;
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/data/sync/remote_ledger_api.dart';
import 'package:opensplit/domain/calendar_date.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_snapshot.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import 'server_reference_data.dart';

/// An in-memory stand-in for one group's Durable Object, per group.
///
/// Faithful about the things that decide whether sync is correct:
///
///  * every committed change takes the next sequence number, and the client
///    can never invent one;
///  * one number per change, not per row, so an expense and its snapshot share
///    it and a page can never be cut between them;
///  * it enforces `sum(payers) = sum(shares) = amount`;
///  * a stale base is refused only when applying the write would move money.
///
/// It keeps its state in the app's own row types and speaks the wire types at
/// its edge, the way the real server serializes its rows.
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
  Future<void> Function(api.EntryInput input)? beforeUpsertEntry;

  /// The account this fake answers as. Groups it is not a member of are
  /// refused, and are not listed by [bootstrap].
  String profileId = 'profile-1';

  DateTime _tick() => _now = _now.add(const Duration(milliseconds: 1));

  _FakeGroup _group(String groupId) =>
      _groups[groupId] ??
      (throw const ApiFailure(
        'No such group.',
        retry: api.Retry.permanent,
        code: api.ErrorCode.noGroup,
      ));

  /// Seeds a group as though it had been created and synced already, through
  /// the same path a real create takes.
  Future<Group> seedGroup(Group group, {required Member creator}) async {
    await createGroup(
      api.GroupCreate(
        id: group.id,
        name: group.name,
        defaultCurrency: group.defaultCurrency,
        isDirect: group.isDirect,
        simplifyDebts: group.simplifyDebts,
        memberId: creator.id,
        displayName: creator.displayName,
      ),
      profile: creator.profileId,
    );
    return _group(group.id).meta;
  }

  @override
  Future<api.Bootstrap> bootstrap() async {
    bootstrapCalls++;
    await beforeBootstrap?.call(bootstrapCalls);

    return api.Bootstrap(
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
  Future<api.ChangePage> changes(
    String groupId, {
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
      return api.ChangePage(
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
    int bySeq(int? a, int? b) => a!.compareTo(b!);

    return api.ChangePage(
      groupId: groupId,
      seq: upTo,
      hasMore: hasMore,
      purgedAt: null,
      group: inWindow(group.meta.seq) ? _group$(group.meta) : null,
      members: [
        for (final member
            in group.members.values.toList()
              ..sort((a, b) => bySeq(a.seq, b.seq)))
          if (inWindow(member.seq)) _member$(member),
      ],
      entries: [
        for (final entry
            in group.entries.values.toList()
              ..sort((a, b) => bySeq(a.seq, b.seq)))
          if (inWindow(entry.seq)) _entry$(entry),
      ],
      events: [
        for (final event in group.events)
          if (inWindow(event.seq)) _event$(event),
      ],
    );
  }

  @override
  Future<api.Entry> upsertEntry(String groupId, api.EntryInput input) async {
    upsertCalls++;
    await beforeUpsertEntry?.call(input);

    final group = _group(groupId);
    final stored = group.entries[input.id];
    final incoming = _entryFrom(input, groupId, group, stored);
    _assertBalanced(incoming);

    // A retry that re-minted the id. Answering with the expense already
    // recorded is the whole point of the key existing.
    final key = input.clientKey;
    if (key != null && stored == null) {
      final existing = group.byClientKey[key];
      if (existing != null) return _entry$(group.entries[existing]!);
    }

    if (stored != null) {
      _assertBaseIsCurrent(stored, incoming, input.baseSeq);
      if (!_differs(stored, incoming)) return _entry$(stored);
    }

    final seq = group.nextSeq();
    final written = incoming.copyWith(seq: seq);
    group.entries[input.id] = written;
    if (key != null) group.byClientKey[key] = input.id;
    group.snapshot(written, seq, _tick());
    return _entry$(written);
  }

  /// The entry an input describes. Authorship, creation time and the client
  /// key are the server's to keep; an edit never resurrects a deletion.
  Entry _entryFrom(
    api.EntryInput input,
    String groupId,
    _FakeGroup group,
    Entry? stored,
  ) => Entry(
    id: input.id,
    groupId: groupId,
    kind: input.kind,
    description: input.description,
    categoryId: input.categoryId,
    currency: input.currency,
    amountMinor: input.amountMinor,
    entryDate: parseCalendarDate(input.entryDate),
    splitKind: input.splitKind,
    payers: [
      for (final payer in input.payers)
        EntryPayer(memberId: payer.memberId, amountMinor: payer.amountMinor),
    ],
    shares: [
      for (final share in input.shares)
        EntryShare(
          memberId: share.memberId,
          amountMinor: share.amountMinor,
          weightMicros: share.weightMicros,
        ),
    ],
    fxRate: input.fxRate?.toDouble(),
    fxSource: input.fxSource,
    notes: input.notes,
    createdBy: stored?.createdBy ?? group.actor(profileId),
    createdAt: stored?.createdAt ?? _tick(),
    clientKey: stored?.clientKey ?? input.clientKey,
    deletedAt: stored?.deletedAt,
  );

  @override
  Future<api.Entry> deleteEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  }) => _setDeleted(groupId, entryId, baseSeq, deleted: true);

  @override
  Future<api.Entry> restoreEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  }) => _setDeleted(groupId, entryId, baseSeq, deleted: false);

  Future<api.Entry> _setDeleted(
    String groupId,
    String entryId,
    int baseSeq, {
    required bool deleted,
  }) async {
    final group = _group(groupId);
    final stored =
        group.entries[entryId] ??
        (throw const ApiFailure(
          'No such expense.',
          retry: api.Retry.permanent,
          code: api.ErrorCode.noSuchEntry,
        ));

    // A retry after the server committed but before its answer arrived.
    if (stored.isDeleted == deleted) return _entry$(stored);

    // Deleting always moves money, so it must carry the exact version the
    // device last saw.
    if (stored.seq != baseSeq) throw _stale;

    final seq = group.nextSeq();
    final written = stored.copyWith(
      deletedAt: deleted ? _tick() : null,
      seq: seq,
    );
    group.entries[entryId] = written;
    group.snapshot(written, seq, _tick());
    return _entry$(written);
  }

  @override
  Future<api.Group> createGroup(
    api.GroupCreate input, {
    String? profile,
  }) async {
    final existing = _groups[input.id];
    if (existing != null) return _group$(existing.meta);

    final fake = _FakeGroup(input.id);
    _groups[input.id] = fake;

    final seq = fake.nextSeq();
    final at = _tick();
    fake.meta = Group(
      id: input.id,
      name: input.name,
      defaultCurrency: input.defaultCurrency,
      isDirect: input.isDirect,
      simplifyDebts: input.simplifyDebts,
      createdBy: input.memberId,
      createdAt: at,
      seq: seq,
    );
    fake.members[input.memberId] = Member(
      id: input.memberId,
      groupId: input.id,
      profileId: profile ?? profileId,
      displayName: input.displayName,
      joinedAt: at,
      seq: seq,
    );
    return _group$(fake.meta);
  }

  @override
  Future<api.Group> updateGroup(String groupId, api.GroupUpdate update) async {
    final fake = _group(groupId);
    fake.meta = fake.meta.copyWith(
      name: update.name,
      simplifyDebts: update.simplifyDebts,
      archivedAt: Value(update.archivedAt),
      seq: Value(fake.nextSeq()),
    );
    return _group$(fake.meta);
  }

  @override
  Future<api.Member> addMember(String groupId, api.MemberCreate input) async {
    final fake = _group(groupId);
    final written = Member(
      id: input.id,
      groupId: groupId,
      displayName: input.displayName,
      upiVpa: input.upiVpa,
      joinedAt: _tick(),
      seq: fake.nextSeq(),
    );
    fake.members[input.id] = written;
    return _member$(written);
  }

  @override
  Future<api.Member> updateMember(
    String groupId,
    String memberId,
    api.MemberUpdate update,
  ) async {
    final fake = _group(groupId);
    final stored =
        fake.members[memberId] ??
        (throw const ApiFailure(
          'No such member in this group.',
          retry: api.Retry.permanent,
          code: api.ErrorCode.noSuchMember,
        ));

    final written = stored.copyWith(
      displayName: update.displayName,
      upiVpa: Value(update.upiVpa),
      leftAt: Value(update.leftAt),
      seq: Value(fake.nextSeq()),
    );
    fake.members[memberId] = written;
    return _member$(written);
  }

  // ----------------------------------------------------------- test fixtures

  /// Adds a placeholder to a seeded group without going through the outbox.
  Member seedMember(Member member) {
    final group = _group(member.groupId);
    final written = member.copyWith(seq: Value(group.nextSeq()));
    group.members[member.id] = written;
    return written;
  }

  /// Somebody claims a placeholder, which sets exactly one column.
  Member claimMember(String groupId, String memberId, String claimant) {
    final group = _group(groupId);
    final written = group.members[memberId]!.copyWith(
      profileId: Value(claimant),
      seq: Value(group.nextSeq()),
    );
    group.members[memberId] = written;
    return written;
  }

  /// The server's own view of one member, read without syncing.
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

  /// Writes a profile as the account itself would, stamping it now. The stamp
  /// is the feed's cursor, so seeding two in a row makes the second newer.
  void seedProfile(Profile profile) =>
      profiles[profile.id] = profile.copyWith(updatedAt: Value(_tick()));

  void publishFxRate({
    required String asOf,
    required String currency,
    required double rate,
    String source = 'test',
  }) => _rates.add(
    api.FxRate(asOf: asOf, currency: currency, rate: rate, source_: source),
  );

  /// When set, every rate pull is refused. A missing rate costs an estimate,
  /// never a balance, so a sync carrying money must survive one.
  bool failFxPulls = false;
  int fxPulls = 0;
  String? lastFxSince;

  final Map<String, Profile> profiles = {};
  final List<api.FxRate> _rates = [];

  /// What the last profile pull asked for, which is how a test sees the cursor.
  DateTime? lastProfilesSince;

  /// The one feed still paged on `(updatedAt, id)`. Rows sharing an instant
  /// are ordered by id and resumed by the pair, because a cursor on the
  /// timestamp alone skips the rest of such a batch or re-reads it forever.
  @override
  Future<api.ProfilePage> profileChanges({
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
    return api.ProfilePage(
      profiles: [for (final profile in page) _profile$(profile)],
      cursor: page.lastOrNull?.updatedAt,
      cursorId: page.lastOrNull?.id,
      hasMore: after.length > limit,
    );
  }

  static final _epoch = DateTime.utc(1970);

  @override
  Future<api.ProfileList> profilesByIds(List<String> ids) async =>
      api.ProfileList(
        profiles: [
          for (final id in ids)
            if (profiles[id] case final profile?) _profile$(profile),
        ],
      );

  @override
  Future<api.Profile> updateProfile(api.ProfileUpdate update) async {
    final written = Profile(
      id: profileId,
      displayName: update.displayName,
      upiVpa: update.upiVpa,
      updatedAt: _tick(),
    );
    profiles[profileId] = written;
    return _profile$(written);
  }

  /// What the server holds, mutable so a test can add, withdraw or rename one.
  late final List<api.Currency> serverCurrencies = [
    for (final row in defaultCurrencies)
      api.Currency(
        code: row.code,
        exponent: row.exponent,
        symbol: row.symbol,
        name: row.name,
      ),
  ];

  @override
  Future<api.Reference> reference() async => api.Reference(
    currencies: List.of(serverCurrencies),
    categories: [
      for (final row in defaultCategories)
        api.Category(id: row.id, name: row.name, icon: row.icon),
    ],
  );

  @override
  Future<api.FxPage> fxRates({required String since}) async {
    fxPulls++;
    lastFxSince = since;
    if (failFxPulls) {
      throw const ApiFailure(
        'Rates are unavailable.',
        retry: api.Retry.transient,
      );
    }
    return api.FxPage(
      rates: [
        for (final rate in _rates)
          if (rate.asOf.compareTo(since) >= 0) rate,
      ],
      hasMore: false,
    );
  }

  @override
  Future<void> requestFxBackfill(api.FxBackfillRequest request) async {}

  // --------------------------------------------------------------- the rules

  static const _stale = ApiFailure(
    'This expense changed since you opened it.',
    retry: api.Retry.stale,
    code: api.ErrorCode.staleBase,
  );

  static void _assertBalanced(Entry entry) {
    if (entry.isBalanced) return;
    throw const ApiFailure(
      'This expense does not add up.',
      retry: api.Retry.permanent,
      code: api.ErrorCode.unbalanced,
    );
  }

  /// A stale base is refused only when applying the write would move money.
  static void _assertBaseIsCurrent(Entry stored, Entry incoming, int? base) {
    if (base == null || stored.seq == base) return;
    if (_money(stored) != _money(incoming)) throw _stale;
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

  /// A push that changes nothing spends no sequence number.
  static bool _differs(Entry stored, Entry incoming) =>
      _money(stored) != _money(incoming) ||
      stored.description != incoming.description ||
      stored.categoryId != incoming.categoryId ||
      stored.currency != incoming.currency ||
      stored.entryDate != incoming.entryDate ||
      stored.splitKind != incoming.splitKind ||
      stored.kind != incoming.kind ||
      stored.notes != incoming.notes;

  // -------------------------------------------------------- serializing rows

  static api.Group _group$(Group row) => api.Group(
    id: row.id,
    name: row.name,
    defaultCurrency: row.defaultCurrency,
    isDirect: row.isDirect,
    simplifyDebts: row.simplifyDebts,
    createdBy: row.createdBy ?? '',
    createdAt: row.createdAt,
    archivedAt: row.archivedAt,
    updatedAt: row.createdAt,
    seq: row.seq!,
  );

  static api.Member _member$(Member row) => api.Member(
    id: row.id,
    profileId: row.profileId,
    displayName: row.displayName,
    upiVpa: row.upiVpa,
    joinedAt: row.joinedAt,
    leftAt: row.leftAt,
    updatedAt: row.joinedAt,
    seq: row.seq!,
  );

  static api.Entry _entry$(Entry entry) => api.Entry(
    id: entry.id,
    kind: entry.kind,
    description: entry.description,
    categoryId: entry.categoryId,
    currency: entry.currency,
    amountMinor: entry.amountMinor,
    entryDate: calendarDate(entry.entryDate),
    splitKind: entry.splitKind,
    fxRate: entry.fxRate,
    fxSource: entry.fxSource,
    fxAt: entry.fxAt,
    notes: entry.notes,
    createdBy: entry.createdBy,
    clientKey: entry.clientKey,
    createdAt: entry.createdAt,
    updatedAt: entry.createdAt,
    deletedAt: entry.deletedAt,
    payers: [
      for (final payer in entry.payers)
        api.Payer(memberId: payer.memberId, amountMinor: payer.amountMinor),
    ],
    shares: [
      for (final share in entry.shares)
        api.Share(
          memberId: share.memberId,
          amountMinor: share.amountMinor,
          weightMicros: share.weightMicros,
        ),
    ],
    seq: entry.seq!,
  );

  static api.Event _event$(GroupEventRow row) => api.Event(
    id: row.id,
    actorId: row.actorId,
    createdAt: row.createdAt,
    kind: row.kind,
    subjectId: row.subjectId,
    payload: row.payload,
    seq: row.seq!,
    ordinal: row.ordinal!,
  );

  static api.Profile _profile$(Profile row) => api.Profile(
    id: row.id,
    displayName: row.displayName,
    upiVpa: row.upiVpa,
    updatedAt: row.updatedAt ?? _epoch,
    deletedAt: null,
  );
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

  /// The caller's own member row, which is who the server says wrote a change.
  String actor(String profileId) =>
      members.values
          .where((member) => member.profileId == profileId)
          .firstOrNull
          ?.id ??
      members.keys.first;

  /// The record, written by the thing that committed the change. A snapshot
  /// identical to the previous one appends nothing, as on the real server.
  void snapshot(Entry entry, int seq, DateTime at) {
    final payload = snapshotOf(entry).toJson();

    final previous = events
        .where((event) => event.subjectId == entry.id)
        .lastOrNull;
    if (previous != null && '${previous.payload}' == '$payload') return;

    events.add(
      GroupEventRow(
        id: 'event-${events.length + 1}',
        groupId: id,
        actorId: entry.createdBy,
        createdAt: at,
        kind: api.EventKind.entry,
        subjectId: entry.id,
        payload: payload,
        seq: seq,
        ordinal: events.where((event) => event.seq == seq).length,
        isProvisional: false,
      ),
    );
  }
}
