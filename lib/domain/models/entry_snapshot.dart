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

    /// Whether this was a bill or somebody paying somebody back.
    ///
    /// Carried because the server records it, and a snapshot that dropped it
    /// could not tell a settlement turning into an expense from no change at
    /// all -- which is a change of what the money means, recorded as silence.
    required EntryKind kind,
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
  kind: entry.kind,
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

/// Reads an `entry` event's payload back into a snapshot.
///
/// The inverse of [snapshotPayload], and the two are deliberately adjacent: a
/// field added to one and forgotten in the other is the bug this pairing exists
/// to make obvious. The keys are the server's, spelled exactly as `snapshotOf`
/// in `server/src/do/group/events.ts` builds them.
///
/// Unknown values are tolerated where the app can carry on — a kind or a split
/// rule this release has never heard of still describes a real amount somebody
/// spent, and refusing to render it would blank a feed rather than a word.
EntrySnapshot snapshotFromPayload({
  required String id,
  required String entryId,
  required String groupId,
  required String? actorId,
  required DateTime createdAt,
  required Map<String, Object?> payload,
  bool isProvisional = false,
}) => EntrySnapshot(
  id: id,
  entryId: entryId,
  groupId: groupId,
  actorId: actorId,
  createdAt: createdAt,
  kind: _enumOr(EntryKind.values, payload['kind'], EntryKind.expense),
  description: payload['description'] as String? ?? '',
  currency: payload['currency'] as String? ?? '',
  amountMinor: (payload['amountMinor'] as num?)?.toInt() ?? 0,
  entryDate: DateTime.parse(payload['entryDate'] as String),
  splitKind: _enumOr(SplitKind.values, payload['splitKind'], SplitKind.equal),
  categoryId: payload['categoryId'] as String?,
  notes: payload['notes'] as String?,
  deletedAt: payload['deletedAt'] == null
      ? null
      : DateTime.parse(payload['deletedAt'] as String),
  payers: _amounts(payload['payers']),
  shares: _amounts(payload['shares']),
  isProvisional: isProvisional,
);

/// The named value, or [fallback] for one this release does not know.
T _enumOr<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// The payload this device would write for [snapshot].
///
/// Used for the provisional row only. The authoritative one is built by
/// `snapshotOf` in the same transaction as the change, and this has to produce
/// the identical shape — a provisional row and the server's account of the same
/// change are compared by nothing, but they are rendered by the same code, and
/// a key spelled differently here would surface as a feed line that changed its
/// mind when the sync landed.
///
/// `deletedAt` is written in UTC with a trailing Z, matching what the server
/// renders. A local-time string would be the same instant said differently,
/// which is exactly the ambiguity the server canonicalises away.
///
/// `entryDate` is deliberately NOT converted: it is a calendar date rather than
/// an instant, and pushing it through UTC would move it to the previous day for
/// anybody east of Greenwich.
Map<String, Object?> snapshotPayload(EntrySnapshot snapshot) => {
  'kind': snapshot.kind.name,
  'description': snapshot.description,
  'currency': snapshot.currency,
  'amountMinor': snapshot.amountMinor,
  'entryDate': _calendarDate(snapshot.entryDate),
  'splitKind': snapshot.splitKind.name,
  'categoryId': snapshot.categoryId,
  'notes': snapshot.notes,
  'deletedAt': snapshot.deletedAt?.toUtc().toIso8601String(),
  'payers': [
    for (final row in snapshot.payers)
      {'memberId': row.memberId, 'amountMinor': row.amountMinor},
  ],
  'shares': [
    for (final row in snapshot.shares)
      {'memberId': row.memberId, 'amountMinor': row.amountMinor},
  ],
};

/// `YYYY-MM-DD`, from the date's own fields rather than from any timezone.
String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `[{"memberId": "...", "amountMinor": 40000}, ...]`.
///
/// Sorted on the way in as well as out. The server orders by member id when it
/// builds the array so two snapshots of an unchanged split compare equal there;
/// sorting here too means a locally written provisional row and the server's
/// account of the same change diff identically.
List<MemberAmount> _amounts(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final row in raw)
      if (row is Map)
        MemberAmount(
          memberId: row['memberId'] as String,
          amountMinor: (row['amountMinor'] as num).toInt(),
        ),
  ]..sort((a, b) => a.memberId.compareTo(b.memberId));
}
