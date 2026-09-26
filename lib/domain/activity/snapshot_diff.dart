import 'package:opensplit_api/opensplit_api.dart' as api;

import '../models/entry_event.dart';
import '../models/group_event.dart';

/// Turns two consecutive `entry` events into the feed line between them.
EntryChanged describeSnapshot({
  GroupEventRow? previous,
  required GroupEventRow current,
}) {
  final before = previous?.entry;
  final after =
      current.entry ?? (throw StateError('${current.id} is not an expense.'));
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
    // A bill becoming a repayment changes what the money means, not just how it
    // reads.
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
bool recordsSameShape(api.EntrySnapshot a, api.EntrySnapshot b) =>
    a.deletedAt == b.deletedAt && diffSnapshots(a, b).isEmpty;
