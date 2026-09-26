/// Turns a computed diff into something a person can read.
library;

import '../activity/snapshot_diff.dart';
import '../models/currency.dart';
import '../models/entry_event.dart';

/// One rendered line, e.g. "the amount, from ₹400.00 to ₹300.00".
String describeChange(
  FieldChange change, {
  Currency? currency,
  Map<String, String>? memberNames,
}) {
  final label = _label(change.field, memberNames);
  final from = _value(change.field, change.from, currency);
  final to = _value(change.field, change.to, currency);

  if (from == null && to == null) return label;
  if (from == null) return '$label, set to $to';
  if (to == null) return '$label, cleared';
  return '$label, from $from to $to';
}

/// The human name for a field, including the per-member ones.
String _label(String field, Map<String, String>? memberNames) {
  final separator = field.indexOf(':');
  if (separator < 0) return _labels[field] ?? field.replaceAll('_', ' ');

  final prefix = field.substring(0, separator);
  final memberId = field.substring(separator + 1);
  final who = memberNames?[memberId];
  final name = (who == null || who.trim().isEmpty) ? 'someone' : who.trim();

  return switch (prefix) {
    shareFieldPrefix => "$name's share",
    paidFieldPrefix => 'what $name paid',
    _ => '$name, $prefix',
  };
}

/// What the event itself was, without the detail.
String describeKind(EntryEventKind kind) => switch (kind) {
  EntryEventKind.created => 'added this',
  EntryEventKind.edited => 'edited this',
  EntryEventKind.deleted => 'deleted this',
  EntryEventKind.restored => 'restored this',
};

const _labels = {
  'amount_minor': 'the amount',
  'description': 'the description',
  'entry_date': 'the date',
  'category_id': 'the category',
  'split_kind': 'how it splits',
  'currency': 'the currency',
  'notes': 'the notes',
  'kind': 'what this is',
};

const _entryKinds = {'expense': 'an expense', 'settlement': 'a repayment'};

const _splitKinds = {
  'equal': 'equally',
  'exact': 'by exact amounts',
  'shares': 'by shares',
  'percent': 'by percentage',
};

/// Renders one side of a change in the units the group thinks in.
String? _value(String field, String? raw, Currency? currency) {
  if (raw == null || raw.isEmpty) return null;

  switch (field.split(':').first) {
    case 'amount_minor':
    case shareFieldPrefix:
    case paidFieldPrefix:
      final minor = int.tryParse(raw);
      if (minor == null || currency == null) return raw;
      final divisor = _pow10(currency.exponent);
      final units = minor ~/ divisor;
      final fraction = (minor % divisor).toString().padLeft(
        currency.exponent,
        '0',
      );
      return currency.exponent == 0
          ? '${currency.symbol}$units'
          : '${currency.symbol}$units.$fraction';

    case 'split_kind':
      return _splitKinds[raw] ?? raw;

    case 'kind':
      return _entryKinds[raw] ?? raw;

    // A category id is meaningless to a reader, and resolving it here would
    // drag the category list into a pure function for one line of text.
    case 'category_id':
      return 'a different category';

    default:
      return raw;
  }
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
