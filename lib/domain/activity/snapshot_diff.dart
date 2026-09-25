import 'package:opensplit_api/opensplit_api.dart' as api;

import '../models/entry_event.dart';
import '../models/group_event.dart';

/// Turns two consecutive `entry` events into the feed line between them.
///
/// The server records only what an expense looked like after each change; the
/// difference is worked out here. That is the security property: no client
/// can describe its own edit, so a Rs.400 to Rs.4,000 rewrite cannot be filed
/// as a small correction, and a re-split that moves money between members
/// cannot go unrecorded.
///
/// [previous] is null for the first snapshot an expense ever had, which is what
/// makes it a creation.
EntryChanged describeSnapshot({
  GroupEventRow? previous,
  required GroupEventRow current,
}) {
  final before = previous?.snapshot;
  final after = current.snapshot;
  final wasDeleted = before?.deletedAt != null;
  final isDeleted = after.deletedAt != null;

  final kind = switch ((before, wasDeleted, isDeleted)) {
    (null, _, _) => EntryEventKind.created,
    (_, false, true) => EntryEventKind.deleted,
    (_, true, false) => EntryEventKind.restored,
    _ => EntryEventKind.edited,
  };

  return EntryChanged(
    id: current.id,
    groupId: current.groupId,
    actorId: current.actorId,
    createdAt: current.createdAt,
    isProvisional: current.isProvisional,
    entryId: current.subjectId ?? '',
    kind: kind,
    // A deletion or a restoration is fully described by what it is.
    changes: kind == EntryEventKind.edited && before != null
        ? diffSnapshots(before, after)
        : const [],
  );
}

List<FieldChange> diffSnapshots(
  api.EntrySnapshot before,
  api.EntrySnapshot after,
) {
  final changes = <FieldChange>[
    ..._changed('description', before.description, after.description),
    ..._changed(
      'amount_minor',
      before.amountMinor.toString(),
      after.amountMinor.toString(),
    ),
    ..._changed('currency', before.currency, after.currency),
    ..._changed('entry_date', before.entryDate, after.entryDate),
    ..._changed('category_id', before.categoryId, after.categoryId),
    ..._changed('split_kind', before.splitKind.value, after.splitKind.value),
    // A bill becoming a repayment changes what the money means, not just how
    // it reads. Left out, the server still records the change -- it dedupes on
    // the payload, which differs -- and the feed renders an edit listing
    // nothing, which is the "somebody edited nothing" line in a worse disguise.
    ..._changed('kind', before.kind.value, after.kind.value),
    ..._changed('notes', before.notes, after.notes),
    ..._diffMembers('share', before.shares, after.shares),
    ..._diffMembers('paid', before.payers, after.payers),
  ];
  changes.sort((a, b) => a.field.compareTo(b.field));
  return changes;
}

/// Prefix on a per-member field, e.g. `share:<memberId>`.
const shareFieldPrefix = 'share';

/// Prefix on a per-member payment field, e.g. `paid:<memberId>`.
const paidFieldPrefix = 'paid';

/// Who owes what, and who put money down, member by member.
///
/// The half that matters most. An edit that rewrites the split while leaving the total alone moves real
/// money between people, satisfies the balance invariant, and changes no number
/// a casual reader would think to check. Reported per member rather than as
/// "the split changed", because the useful sentence names who gained and who
/// lost.
Iterable<FieldChange> _diffMembers(
  String prefix,
  List<api.MoneyRow> before,
  List<api.MoneyRow> after,
) {
  final was = {for (final row in before) row.memberId: row.amountMinor};
  final now = {for (final row in after) row.memberId: row.amountMinor};

  return [
    for (final memberId in {...was.keys, ...now.keys}.toList()..sort())
      if (was[memberId] != now[memberId])
        FieldChange(
          field: '$prefix:$memberId',
          from: was[memberId]?.toString(),
          to: now[memberId]?.toString(),
        ),
  ];
}

/// One change, or nothing at all.
///
/// Empty and null are treated as the same absence. The editor writes '' for a
/// description nobody typed and the server holds null, so comparing them
/// literally would report an edit every time a row made the round trip.
Iterable<FieldChange> _changed(String field, String? from, String? to) {
  final a = (from ?? '').trim();
  final b = (to ?? '').trim();
  if (a == b) return const [];
  return [
    FieldChange(
      field: field,
      from: a.isEmpty ? null : a,
      to: b.isEmpty ? null : b,
    ),
  ];
}

/// Whether two snapshots record the same state of an expense.
///
/// The local half of the server's dedup rule. A re-saved editor and a retried
/// write both produce a snapshot identical to the one before it, and without
/// this the feed would carry a line for each -- lines that would then vanish
/// when the server's account arrived, having deduped them. "Priya edited
/// nothing" is worse than no line at all.
bool recordsSameShape(api.EntrySnapshot a, api.EntrySnapshot b) =>
    a.deletedAt == b.deletedAt && diffSnapshots(a, b).isEmpty;
