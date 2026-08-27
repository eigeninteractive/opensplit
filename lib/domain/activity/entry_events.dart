import '../models/entry.dart';
import '../models/entry_event.dart';

/// Works out what changed when an entry was written, as a feed line.
///
/// This is the client-side twin of what used to be a Postgres trigger, and
/// moving it here is not a preference — it is what makes the activity feed obey
/// the same rule as everything else in the app. Every screen renders from the
/// local database, and every local write is complete on its own. The one
/// exception was this: an expense saved on the device appeared instantly, while
/// the record of it being saved existed only after a round trip to a server.
/// Offline, or as a guest with no reachable backend, the feed was empty
/// forever — an audit trail that could not describe the thing it was watching.
///
/// The old argument for the trigger was that a record a device can author is
/// not a record. That does not survive contact with a local-first ledger: the
/// device already authors the expenses themselves, and the server takes them on
/// trust bounded by row-level security. A client that wanted to lie about who
/// spent what could simply write the expense that way. What the server can
/// still guarantee — and now does, through `entry_events_insert` rather than a
/// SECURITY DEFINER function — is that you may only append events attributed to
/// your own member row, in a group you belong to, and may never revise or
/// delete one afterwards. That is the same guarantee, without the pretence.
///
/// Returns null when there is nothing worth recording, which is the same set of
/// cases the trigger declined to write:
///
///  * no [actorId] — a write with nobody to attribute it to would be a row the
///    feed cannot render;
///  * an edit that changed none of the fields below, which is what a re-saved
///    editor and a retried sync both look like. A feed full of "Ravi edited
///    nothing" is worse than no feed.
EntryEvent? describeEntryWrite({
  required Entry? before,
  required Entry after,
  required String? actorId,
  required String id,
  required DateTime at,
}) {
  if (actorId == null) return null;

  final EntryEventKind kind;
  var changes = const <FieldChange>[];

  if (before == null) {
    kind = EntryEventKind.created;
  } else if (!before.isDeleted && after.isDeleted) {
    kind = EntryEventKind.deleted;
  } else if (before.isDeleted && !after.isDeleted) {
    kind = EntryEventKind.restored;
  } else {
    changes = _diff(before, after);
    if (changes.isEmpty) return null;
    kind = EntryEventKind.edited;
  }

  return EntryEvent(
    id: id,
    entryId: after.id,
    groupId: after.groupId,
    actorId: actorId,
    kind: kind,
    createdAt: at,
    changes: changes,
  );
}

/// Only the fields a person would recognise as "the expense changing".
///
/// Deliberately not payers and shares. They move on almost every edit as a
/// consequence of the amount or the split rule changing, so including them
/// would bury the one line that says what actually happened under a dozen that
/// restate it per member.
///
/// `fx_at` moves whenever `fx_rate` does and would double every currency edit;
/// `updated_at` changes on every write by definition, and would make a save
/// that altered nothing look like an edit. Neither is here, and the names are
/// the server's column names because that is what the stored diff has always
/// used and what [describeChange] renders.
List<FieldChange> _diff(Entry before, Entry after) {
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
  ];
  // The same stable order the wire format is read back in, so an event reads
  // identically whether it was written here or pulled from another device.
  changes.sort((a, b) => a.field.compareTo(b.field));
  return changes;
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

/// `entry_date` is a Postgres `date`, and the diff has always held its text
/// form. Matching it here keeps a locally written event byte-identical to the
/// one another device pulls.
String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
