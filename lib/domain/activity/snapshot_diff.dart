import '../models/entry_event.dart';
import '../models/entry_snapshot.dart';

/// Turns two consecutive snapshots into the feed line between them.
///
/// This is where the activity feed is actually produced. Nothing on the wire
/// says what changed: the server records only what each expense looked like
/// after each change, and the difference is worked out here, from two records
/// this device did not author.
///
/// That indirection is the entire security property. While the client composed
/// the diff, it could describe its own edit however it liked -- a Rs.400 to
/// Rs.4,000 rewrite could be filed as a ten-rupee correction, and nothing on
/// the server compared the claim against the expense. Worse, it could rewrite
/// the shares alone, moving money between members while the total stayed put,
/// and simply write no history at all. Deriving the line from server-written
/// snapshots leaves nothing to assert and therefore nothing to falsify.
///
/// [previous] is null for the first snapshot an expense ever had, which is what
/// makes it a creation.
EntryEvent describeSnapshot({
  EntrySnapshot? previous,
  required EntrySnapshot current,
}) {
  final wasDeleted = previous?.deletedAt != null;
  final isDeleted = current.deletedAt != null;

  final kind = switch ((previous, wasDeleted, isDeleted)) {
    (null, _, _) => EntryEventKind.created,
    (_, false, true) => EntryEventKind.deleted,
    (_, true, false) => EntryEventKind.restored,
    _ => EntryEventKind.edited,
  };

  return EntryEvent(
    id: current.id,
    entryId: current.entryId,
    groupId: current.groupId,
    actorId: current.actorId,
    kind: kind,
    createdAt: current.createdAt,
    // A deletion or a restoration is fully described by what it is. Listing
    // the fields that happen to differ alongside it would bury the one word
    // that matters.
    changes: kind == EntryEventKind.edited && previous != null
        ? diffSnapshots(previous, current)
        : const [],
    isProvisional: current.isProvisional,
  );
}

/// Every field that moved between two snapshots, in a stable order.
List<FieldChange> diffSnapshots(EntrySnapshot before, EntrySnapshot after) {
  final changes = <FieldChange>[
    ..._changed('description', before.description, after.description),
    ..._changed(
      'amount_minor',
      before.amountMinor.toString(),
      after.amountMinor.toString(),
    ),
    ..._changed('currency', before.currency, after.currency),
    ..._changed(
      'entry_date',
      _dateOnly(before.entryDate),
      _dateOnly(after.entryDate),
    ),
    ..._changed('category_id', before.categoryId, after.categoryId),
    ..._changed('split_kind', before.splitKind.name, after.splitKind.name),
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
/// The half that used to be missing entirely, and the half that matters most.
/// An edit that rewrites the split while leaving the total alone moves real
/// money between people, satisfies the balance invariant, and changes no number
/// a casual reader would think to check. Reported per member rather than as
/// "the split changed", because the useful sentence names who gained and who
/// lost.
Iterable<FieldChange> _diffMembers(
  String prefix,
  List<MemberAmount> before,
  List<MemberAmount> after,
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

/// `entry_date` is a Postgres `date`, and the snapshot holds it as one.
String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Whether two snapshots record the same state of an expense.
///
/// The local half of the server's dedup rule. A re-saved editor and a retried
/// write both produce a snapshot identical to the one before it, and without
/// this the feed would carry a line for each -- lines that would then vanish
/// when the server's account arrived, having deduped them. "Priya edited
/// nothing" is worse than no line at all.
bool recordsSameShape(EntrySnapshot a, EntrySnapshot b) =>
    a.deletedAt == b.deletedAt && diffSnapshots(a, b).isEmpty;
