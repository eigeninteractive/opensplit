/// Turns a stored diff into something a person can read.
///
/// Kept in the domain, away from widgets, because the awkward part is not
/// layout: it is that the server stores what changed in the columns' own terms
/// — `amount_minor`, `split_kind`, minor units, enum names — and a feed has to
/// say it the way the people in the group would.
///
/// Unknown fields are rendered rather than dropped. A column added to the
/// trigger's diff later should show up as a plain, slightly clumsy line
/// instead of silently disappearing from the record.
library;

import '../models/currency.dart';
import '../models/entry_event.dart';

/// One rendered line, e.g. "the amount, from ₹400.00 to ₹300.00".
String describeChange(FieldChange change, {Currency? currency}) {
  final label = _labels[change.field] ?? change.field.replaceAll('_', ' ');
  final from = _value(change.field, change.from, currency);
  final to = _value(change.field, change.to, currency);

  if (from == null && to == null) return label;
  if (from == null) return '$label, set to $to';
  if (to == null) return '$label, cleared';
  return '$label, from $from to $to';
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
};

const _splitKinds = {
  'equal': 'equally',
  'exact': 'by exact amounts',
  'shares': 'by shares',
  'percent': 'by percentage',
};

/// Renders one side of a change in the units the group thinks in.
///
/// Amounts are the reason this exists: the column holds minor units, so an
/// unrendered diff reads "from 40000 to 30000" for what everybody involved
/// remembers as ₹400 and ₹300.
String? _value(String field, String? raw, Currency? currency) {
  if (raw == null || raw.isEmpty) return null;

  switch (field) {
    case 'amount_minor':
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
