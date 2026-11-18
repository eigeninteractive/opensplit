/// Turns a computed diff into something a person can read.
library;

import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../data/local/database.dart';
import '../activity/snapshot_diff.dart';
import '../models/entry_event.dart';
import '../money_format.dart';

/// One rendered line, e.g. "Amount changed from ₹400.00 to ₹300.00".
///
/// [categoryNames] maps category ids to their names. Without it a category
/// change still says that the category changed, just not to what.
String describeChange(
  FieldChange change, {
  Currency? currency,
  Map<String, String>? memberNames,
  Map<String, String>? categoryNames,
}) {
  final label = _label(change.field, memberNames);
  final from = _value(change.field, change.from, currency, categoryNames);
  final to = _value(change.field, change.to, currency, categoryNames);

  if (from == null && to == null) return '$label changed';
  if (from == null) return '$label set to $to';
  if (to == null) return '$label cleared';
  return '$label changed from $from to $to';
}

/// The human name for a field, including the per-member ones.
String _label(String field, Map<String, String>? memberNames) {
  final separator = field.indexOf(':');
  if (separator < 0) return _labels[field] ?? _sentenceCase(field);

  final prefix = field.substring(0, separator);
  final memberId = field.substring(separator + 1);
  final who = memberNames?[memberId];
  final name = (who == null || who.trim().isEmpty) ? 'Someone' : who.trim();

  return switch (prefix) {
    shareFieldPrefix => "$name's share",
    paidFieldPrefix => 'Amount $name paid',
    _ => '$name, $prefix',
  };
}

String _sentenceCase(String field) {
  final words = field.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// What the event itself was, without the detail, on the expense's own page
/// where the expense needs no naming: "added this expense".
String describeKind(EntryEventKind kind, {bool isPayment = false}) {
  final noun = isPayment ? 'this payment' : 'this expense';
  return '${_verb(kind, isPayment: isPayment)} $noun';
}

String _verb(EntryEventKind kind, {required bool isPayment}) => switch (kind) {
  EntryEventKind.created => isPayment ? 'recorded' : 'added',
  EntryEventKind.edited => 'edited',
  EntryEventKind.deleted => 'deleted',
  EntryEventKind.restored => 'restored',
};

/// A feed line naming the expense or payment it is about, e.g.
/// "Seenu added “Fuel”" or "Seenu recorded a payment from Brinda to Seenu".
///
/// [snapshot] is the entry as the event left it. [fallbackDescription] is used
/// for older events that carry none.
String describeEntryEvent({
  required String actor,
  required EntryEventKind kind,
  api.EntrySnapshot? snapshot,
  String? fallbackDescription,
  Map<String, String> memberNames = const {},
}) {
  final isPayment = snapshot?.kind == api.EntryKind.settlement;
  final verb = _verb(kind, isPayment: isPayment);
  if (isPayment) {
    final from = _nameOf(snapshot!.payers.firstOrNull?.memberId, memberNames);
    final to = _nameOf(snapshot.shares.firstOrNull?.memberId, memberNames);
    final parties = from == null || to == null ? '' : ' from $from to $to';
    return '$actor $verb a payment$parties';
  }
  final description = (snapshot?.description ?? fallbackDescription ?? '')
      .trim();
  return description.isEmpty
      ? '$actor $verb an expense'
      : '$actor $verb “$description”';
}

/// What an entry came to and who paid it, for the line that records it
/// being added or removed, e.g. "₹800.00 · paid by Seenu".
String? describeEntrySummary(
  api.EntrySnapshot? snapshot, {
  Currency? currency,
  Map<String, String> memberNames = const {},
}) {
  if (snapshot == null) return null;
  final amount = formatMoney(currency, snapshot.amountMinor);
  if (snapshot.kind == api.EntryKind.settlement) return amount;
  final payers = [
    for (final payer in snapshot.payers) ?_nameOf(payer.memberId, memberNames),
  ];
  return payers.isEmpty ? amount : '$amount · paid by ${payers.join(', ')}';
}

String? _nameOf(String? memberId, Map<String, String> memberNames) {
  final name = memberNames[memberId]?.trim();
  return name == null || name.isEmpty ? null : name;
}

const _labels = {
  'amount_minor': 'Amount',
  'description': 'Description',
  'entry_date': 'Date',
  'category_id': 'Category',
  'split_kind': 'Split',
  'currency': 'Currency',
  'notes': 'Notes',
  'kind': 'Type',
};

const _entryKinds = {'expense': 'expense', 'settlement': 'payment'};

const _splitKinds = {
  'equal': 'equal',
  'exact': 'exact amounts',
  'shares': 'shares',
  'percent': 'percentages',
};

/// Renders one side of a change in the units the group thinks in, or null
/// when there is nothing a reader could use.
String? _value(
  String field,
  String? raw,
  Currency? currency,
  Map<String, String>? categoryNames,
) {
  if (raw == null || raw.isEmpty) return null;

  switch (field.split(':').first) {
    case 'amount_minor':
    case shareFieldPrefix:
    case paidFieldPrefix:
      final minor = int.tryParse(raw);
      if (minor == null || currency == null) return raw;
      return formatMoney(currency, minor);

    case 'entry_date':
      final date = DateTime.tryParse(raw);
      return date == null ? raw : DateFormat.yMMMd().format(date);

    case 'split_kind':
      return _splitKinds[raw] ?? raw;

    case 'kind':
      return _entryKinds[raw] ?? raw;

    // An id is meaningless to a reader: without its name, say nothing and
    // let the line read "Category changed".
    case 'category_id':
      return categoryNames?[raw];

    default:
      return raw;
  }
}
