import 'package:opensplit_api/opensplit_api.dart' as api;

import 'api_client.dart';

/// The part of the API the sync engine uses, in the generated wire types.
///
/// An interface only so the sync suites can run against an in-memory server
/// (`test/data/fake_remote_ledger.dart`); the types are the contract's own, so
/// there is nothing to translate on either side of it. Every method throws
/// [ApiFailure] on a refusal or a transport failure.
abstract interface class RemoteLedgerApi {
  Future<api.Bootstrap> bootstrap();

  /// One page of one group's changes after [since]. `limit` counts changes,
  /// not rows, so a page never holds half of one.
  Future<api.ChangePage> changes(
    String groupId, {
    required int since,
    required int limit,
  });

  /// Records or edits an expense whole. `input.baseSeq` is the version the
  /// edit was composed against; a stale base that would move money is refused
  /// with [api.Retry.stale].
  Future<api.Entry> upsertEntry(String groupId, api.EntryInput input);

  Future<api.Entry> deleteEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  });

  Future<api.Entry> restoreEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  });

  /// Creates the group and its creator's member row in one change.
  Future<api.Group> createGroup(api.GroupCreate input);

  Future<api.Group> updateGroup(String groupId, api.GroupUpdate update);

  Future<api.Member> addMember(String groupId, api.MemberCreate input);

  Future<api.Member> updateMember(
    String groupId,
    String memberId,
    api.MemberUpdate update,
  );

  /// Profiles changed after the `(since, sinceId)` keyset cursor. Both halves
  /// or neither.
  Future<api.ProfilePage> profileChanges({
    DateTime? since,
    String? sinceId,
    required int limit,
  });

  /// Exactly these profiles: the ones a cursor cannot surface because they
  /// became visible (a placeholder was claimed) after the cursor passed them.
  Future<api.ProfileList> profilesByIds(List<String> ids);

  Future<api.Profile> updateProfile(api.ProfileUpdate update);

  Future<api.Reference> reference();

  /// Rates published on or after [since] (`yyyy-MM-dd`).
  Future<api.FxPage> fxRates({required String since});

  /// Fire and forget: the rate arrives on a later sync, or does not.
  Future<void> requestFxBackfill(api.FxBackfillRequest request);
}

/// [RemoteLedgerApi] over the generated client.
class CloudflareLedgerApi implements RemoteLedgerApi {
  CloudflareLedgerApi(api.OpensplitApi client)
    : _sync = client.getSyncApi(),
      _groups = client.getGroupsApi(),
      _entries = client.getEntriesApi(),
      _reference = client.getReferenceApi();

  final api.SyncApi _sync;
  final api.GroupsApi _groups;
  final api.EntriesApi _entries;
  final api.ReferenceApi _reference;

  @override
  Future<api.Bootstrap> bootstrap() => fetch(_sync.bootstrap());

  @override
  Future<api.ChangePage> changes(
    String groupId, {
    required int since,
    required int limit,
  }) => fetch(_sync.getChanges(groupId: groupId, since: since, limit: limit));

  @override
  Future<api.Entry> upsertEntry(String groupId, api.EntryInput input) =>
      fetch(_entries.upsertEntry(groupId: groupId, entryInput: input));

  @override
  Future<api.Entry> deleteEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  }) => fetch(
    _entries.deleteEntry(groupId: groupId, entryId: entryId, baseSeq: baseSeq),
  );

  @override
  Future<api.Entry> restoreEntry(
    String groupId,
    String entryId, {
    required int baseSeq,
  }) => fetch(
    _entries.restoreEntry(groupId: groupId, entryId: entryId, baseSeq: baseSeq),
  );

  @override
  Future<api.Group> createGroup(api.GroupCreate input) =>
      fetch(_groups.createGroup(groupCreate: input));

  @override
  Future<api.Group> updateGroup(String groupId, api.GroupUpdate update) =>
      fetch(_groups.updateGroup(groupId: groupId, groupUpdate: update));

  @override
  Future<api.Member> addMember(String groupId, api.MemberCreate input) =>
      fetch(_groups.addMember(groupId: groupId, memberCreate: input));

  @override
  Future<api.Member> updateMember(
    String groupId,
    String memberId,
    api.MemberUpdate update,
  ) => fetch(
    _groups.updateMember(
      groupId: groupId,
      memberId: memberId,
      memberUpdate: update,
    ),
  );

  @override
  Future<api.ProfilePage> profileChanges({
    DateTime? since,
    String? sinceId,
    required int limit,
  }) => fetch(_sync.getProfiles(since: since, sinceId: sinceId, limit: limit));

  @override
  Future<api.ProfileList> profilesByIds(List<String> ids) =>
      fetch(_sync.getProfilesByIds(ids: ids.join(',')));

  @override
  Future<api.Profile> updateProfile(api.ProfileUpdate update) =>
      fetch(_sync.updateProfile(profileUpdate: update));

  @override
  Future<api.Reference> reference() => fetch(_reference.getReference());

  @override
  Future<api.FxPage> fxRates({required String since}) =>
      fetch(_reference.getFxRates(since: since));

  @override
  Future<void> requestFxBackfill(api.FxBackfillRequest request) =>
      fetch(_reference.requestFxBackfill(fxBackfillRequest: request));
}
