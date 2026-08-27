import 'package:freezed_annotation/freezed_annotation.dart';

import '../split/splitter.dart';
import 'entry.dart';

part 'entry_snapshot.freezed.dart';

/// One member's stake in a snapshot: what they put in, or what they owe.
///
/// Deliberately not [EntryPayer] or [EntryShare]. Those carry the live
/// entry's structure -- a share knows the weight rule that produced it -- and a
/// snapshot is a photograph, not a thing to recompute from. Reusing them would
/// invite exactly that.
@freezed
abstract class MemberAmount with _$MemberAmount {
  const factory MemberAmount({
    required String memberId,
    required int amountMinor,
  }) = _MemberAmount;
}

/// What an expense looked like at one moment, and who had just changed it.
///
/// Written by the server, in the same transaction as the change, and never
/// revised. The activity feed is the difference between consecutive snapshots,
/// computed by whoever reads them -- see `describeSnapshot`.
///
/// The device writes its own [isProvisional] snapshot as well, so the feed
/// works offline and as a guest. That one is never pushed and is dropped as
/// soon as the server's account of the same expense arrives.
///
/// Nothing is ever rebuilt from these. Balances read entries, and only entries.
@freezed
abstract class EntrySnapshot with _$EntrySnapshot {
  const factory EntrySnapshot({
    required String id,
    required String entryId,
    required String groupId,

    /// The member who made the change, not the account: authorship is
    /// group-scoped, so a placeholder's edits survive them claiming an account.
    ///
    /// Null when the change came from something with no member row at all. A
    /// change nobody can be named for still has to be on the record; silence
    /// would be the worse answer.
    required String? actorId,
    required DateTime createdAt,
    required String description,
    required String currency,
    required int amountMinor,
    required DateTime entryDate,
    required SplitKind splitKind,
    String? categoryId,
    String? notes,

    /// Set once the expense is soft-deleted. What makes "deleted" and
    /// "restored" readable off the chain without a column asserting them.
    DateTime? deletedAt,
    @Default(<MemberAmount>[]) List<MemberAmount> payers,
    @Default(<MemberAmount>[]) List<MemberAmount> shares,

    /// Written by this device and not yet replaced by the server's account of
    /// the same expense. Local only; there is no such column on the server.
    @Default(false) bool isProvisional,
  }) = _EntrySnapshot;
}

/// The snapshot this device would record for [entry], right now.
///
/// Used only for the provisional row. The authoritative one is taken by the
/// server, from the row it actually committed.
EntrySnapshot snapshotOf(
  Entry entry, {
  required String id,
  required String? actorId,
  required DateTime at,
}) => EntrySnapshot(
  id: id,
  entryId: entry.id,
  groupId: entry.groupId,
  actorId: actorId,
  createdAt: at,
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
      MemberAmount(memberId: payer.memberId, amountMinor: payer.amountMinor),
  ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
  shares: [
    for (final share in entry.shares)
      MemberAmount(memberId: share.memberId, amountMinor: share.amountMinor),
  ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
  isProvisional: true,
);
