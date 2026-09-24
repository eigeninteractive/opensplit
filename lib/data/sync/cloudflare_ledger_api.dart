import 'package:dio/dio.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/category.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group.dart';
import '../../domain/models/group_event.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import '../../domain/split/splitter.dart';
import 'remote_ledger_api.dart';

/// The app's ledger interface, over the generated client.
///
/// Thin on purpose. Everything below is translation: generated wire types into
/// the freezed models the rest of the app is written against, and the server's
/// refusal vocabulary into [RejectionKind]. There is no decision here that the
/// server has not already made.
///
/// The generated client is regenerated wholesale from `docs/openapi.json` on
/// every wire change, so this file is where a change to the contract shows up
/// as a compile error — which is the point of having it rather than calling
/// the generated APIs from the sync engine directly.
class CloudflareLedgerApi implements RemoteLedgerApi {
  CloudflareLedgerApi(this._client);

  final api.OpensplitApi _client;

  api.SyncApi get _sync => _client.getSyncApi();
  api.GroupsApi get _groups => _client.getGroupsApi();
  api.EntriesApi get _entries => _client.getEntriesApi();

  @override
  Future<RemoteBootstrap> bootstrap() => _guard(() async {
    final body = _required(await _sync.bootstrap());
    return RemoteBootstrap(
      profileId: body.profileId,
      displayName: body.displayName,
      upiVpa: body.upiVpa,
      isAnonymous: body.isAnonymous,
      groupIds: body.groupIds.toList(),
    );
  });

  @override
  Future<GroupChanges> pullChanges({
    required String groupId,
    required int since,
    required int limit,
  }) => _guard(() async {
    final page = _required(
      await _sync.getChanges(groupId: groupId, since: since, limit: limit),
    );

    final group = page.group;
    return GroupChanges(
      groupId: page.groupId,
      seq: page.seq,
      hasMore: page.hasMore,
      purgedAt: page.purgedAt,
      group: group == null ? null : _group(group),
      members: [
        for (final member in page.members) _member(member, page.groupId),
      ],
      entries: [for (final entry in page.entries) _entry(entry, page.groupId)],
      events: [for (final event in page.events) ?_event(event, page.groupId)],
    );
  });

  @override
  Future<Entry> pushEntry(Entry entry) => _guard(() async {
    final stored = _required(
      await _entries.upsertEntry(
        groupId: entry.groupId,
        entryInput: api.EntryInput(
          id: entry.id,
          kind: _entryKind(entry.kind),
          description: entry.description,
          categoryId: entry.categoryId,
          currency: entry.currency,
          amountMinor: entry.amountMinor,
          entryDate: _day(entry.entryDate),
          splitKind: _splitKind(entry.splitKind),
          fxRate: entry.fxRate,
          fxSource: entry.fxSource,
          notes: entry.notes,
          clientKey: entry.clientKey,
          // The version this edit was composed against. Null for a row this
          // device invented, which can never be stale against anything.
          baseSeq: entry.seq,
          payers: [
            for (final payer in entry.payers)
              api.Payer(
                memberId: payer.memberId,
                amountMinor: payer.amountMinor,
              ),
          ],
          shares: [
            for (final share in entry.shares)
              api.Share(
                memberId: share.memberId,
                amountMinor: share.amountMinor,
                weightMicros: share.weightMicros,
              ),
          ],
        ),
      ),
    );
    return _entry(stored, entry.groupId);
  });

  @override
  Future<Entry> deleteEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  }) => _guard(() async {
    final stored = _required(
      await _entries.deleteEntry(
        groupId: groupId,
        entryId: entryId,
        baseSeq: baseSeq,
      ),
    );
    return _entry(stored, groupId);
  });

  @override
  Future<Entry> restoreEntry({
    required String groupId,
    required String entryId,
    required int baseSeq,
  }) => _guard(() async {
    final stored = _required(
      await _entries.restoreEntry(
        groupId: groupId,
        entryId: entryId,
        baseSeq: baseSeq,
      ),
    );
    return _entry(stored, groupId);
  });

  @override
  Future<Group> createGroup(Group group, {required Member creator}) =>
      _guard(() async {
        final stored = _required(
          await _groups.createGroup(
            groupCreate: api.GroupCreate(
              id: group.id,
              name: group.name,
              defaultCurrency: group.defaultCurrency,
              isDirect: group.isDirect,
              simplifyDebts: group.simplifyDebts,
              memberId: creator.id,
              displayName: creator.displayName,
            ),
          ),
        );
        return _group(stored);
      });

  @override
  Future<Group> updateGroup(Group group) => _guard(() async {
    final stored = _required(
      await _groups.updateGroup(
        groupId: group.id,
        groupPatch: api.GroupPatch(
          name: group.name,
          simplifyDebts: group.simplifyDebts,
          archivedAt: group.archivedAt,
        ),
      ),
    );
    return _group(stored);
  });

  @override
  Future<Member> addMember(Member member) => _guard(() async {
    final stored = _required(
      await _groups.addMember(
        groupId: member.groupId,
        memberCreate: api.MemberCreate(
          id: member.id,
          displayName: member.displayName,
          upiVpa: member.upiVpa,
        ),
      ),
    );
    return _member(stored, member.groupId);
  });

  @override
  Future<Member> updateMember(Member member) => _guard(() async {
    final stored = _required(
      await _groups.updateMember(
        groupId: member.groupId,
        memberId: member.id,
        memberPatch: api.MemberPatch(
          displayName: member.displayName,
          upiVpa: member.upiVpa,
          leftAt: member.leftAt,
        ),
      ),
    );
    return _member(stored, member.groupId);
  });

  // Phases 4 and 5. Declared rather than omitted so the interface stays one
  // description of what a backend has to do, and so adding them is a compile
  // error here rather than a discovery at runtime.
  @override
  Future<ProfilePage> pullProfiles({
    DateTime? since,
    String? sinceId,
    required int limit,
  }) async => const ProfilePage.empty();

  @override
  Future<List<Profile>> pullProfilesByIds(List<String> ids) async => const [];

  @override
  Future<Profile> pushProfile(Profile profile) async => profile;

  @override
  Future<List<Currency>> pullCurrencies() async => const [];

  @override
  Future<List<Category>> pullCategories() async => const [];

  @override
  Future<List<RemoteFxRate>> pullFxRates({required String since}) async =>
      const [];

  @override
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  }) async {}

  // ------------------------------------------------------------- translation

  Group _group(api.Group row) => Group(
    id: row.id,
    name: row.name,
    defaultCurrency: row.defaultCurrency,
    isDirect: row.isDirect,
    simplifyDebts: row.simplifyDebts,
    createdBy: row.createdBy,
    createdAt: row.createdAt,
    archivedAt: row.archivedAt,
    seq: row.seq,
  );

  /// The group id comes from the page, not from the row.
  ///
  /// No row on the wire carries one: it is a property of the page, and
  /// repeating it on two hundred entries per sync would be redundancy that
  /// also implied the server stores it that way, which it does not.
  Member _member(api.Member row, String groupId) => Member(
    id: row.id,
    groupId: groupId,
    profileId: row.profileId,
    displayName: row.displayName,
    joinedAt: row.joinedAt,
    leftAt: row.leftAt,
    upiVpa: row.upiVpa,
    seq: row.seq,
  );

  Entry _entry(api.Entry row, String groupId) => Entry(
    id: row.id,
    groupId: groupId,
    kind: _entryKindOf(row.kind),
    description: row.description,
    categoryId: row.categoryId,
    currency: row.currency,
    amountMinor: row.amountMinor,
    entryDate: DateTime.parse(row.entryDate),
    splitKind: _splitKindOf(row.splitKind),
    payers: [
      for (final payer in row.payers)
        EntryPayer(memberId: payer.memberId, amountMinor: payer.amountMinor),
    ],
    shares: [
      for (final share in row.shares)
        EntryShare(
          memberId: share.memberId,
          amountMinor: share.amountMinor,
          weightMicros: share.weightMicros,
        ),
    ],
    fxRate: row.fxRate?.toDouble(),
    fxSource: row.fxSource,
    fxAt: row.fxAt,
    notes: row.notes,
    createdBy: row.createdBy,
    createdAt: row.createdAt,
    seq: row.seq,
    deletedAt: row.deletedAt,
    clientKey: row.clientKey,
  );

  /// Null for a kind this build has never heard of.
  ///
  /// The generated enum decodes an unrecognised value into a sentinel rather
  /// than throwing, which is the whole reason this client is generated with
  /// `dart-dio`. A newer server's new event kind therefore costs one missing
  /// feed line, not the sync page it arrived in.
  GroupEventRow? _event(api.Event row, String groupId) {
    final kind = GroupEventKind.parse(row.kind.value);
    if (kind == null) return null;

    return GroupEventRow(
      id: row.id,
      groupId: groupId,
      actorId: row.actorId,
      createdAt: row.createdAt,
      kind: kind,
      subjectId: row.subjectId,
      payload: Map<String, Object?>.from(row.payload ?? const {}),
      seq: row.seq,
      ordinal: row.ordinal,
    );
  }

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static api.EntryKind _entryKind(EntryKind kind) => switch (kind) {
    EntryKind.expense => api.EntryKind.expense,
    EntryKind.settlement => api.EntryKind.settlement,
  };

  static EntryKind _entryKindOf(api.EntryKind kind) =>
      kind == api.EntryKind.settlement
      ? EntryKind.settlement
      : EntryKind.expense;

  static api.SplitKind _splitKind(SplitKind kind) => switch (kind) {
    SplitKind.equal => api.SplitKind.equal,
    SplitKind.exact => api.SplitKind.exact,
    SplitKind.shares => api.SplitKind.shares,
    SplitKind.percent => api.SplitKind.percent,
  };

  static SplitKind _splitKindOf(api.SplitKind kind) => switch (kind) {
    api.SplitKind.exact => SplitKind.exact,
    api.SplitKind.shares => SplitKind.shares,
    api.SplitKind.percent => SplitKind.percent,
    // Includes the unknown-value sentinel: a split this build cannot name is
    // still an expense with resolved amounts, and 'equal' is the one reading
    // that changes no money.
    _ => SplitKind.equal,
  };

  /// A 200 with no body is a bug on the server, not a state to model.
  static T _required<T>(Response<T> response) {
    final body = response.data;
    if (body == null) {
      throw const RemoteRejected(
        'The server answered with no body.',
        kind: RejectionKind.transient,
      );
    }
    return body;
  }

  /// Turns a refusal into the kind of "no" the outbox knows how to act on.
  ///
  /// Read off `error.retry`, which the server states, rather than inferred
  /// from the status code. That inference does not survive contact with this
  /// API: six refusals are a truthful 409 and only one of them is worth
  /// composing again, so a device reading the number would retry `not_settled`
  /// forever and wedge everything queued behind it.
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == null) {
        throw RemoteRejected(
          error.message ?? 'The request did not complete.',
          kind: RejectionKind.transient,
        );
      }

      final body = error.response?.data;
      final envelope = body is Map ? body['error'] : null;
      final code = envelope is Map ? envelope['code'] as String? : null;
      final message = envelope is Map ? envelope['message'] as String? : null;
      final retry = envelope is Map ? envelope['retry'] as String? : null;

      throw RemoteRejected(
        message ?? 'The server refused the request ($status).',
        code: code,
        kind: switch (retry) {
          'stale' => RejectionKind.stale,
          'permanent' => RejectionKind.permanent,
          'transient' => RejectionKind.transient,
          // No envelope at all means something in front of the Worker
          // answered — a gateway, a proxy, an outage page. 5xx is worth
          // another attempt; anything else is not.
          _ =>
            status >= 500 ? RejectionKind.transient : RejectionKind.permanent,
        },
      );
    }
  }
}
