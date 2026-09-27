import '../../data/local/database.dart';
import '../calendar_date.dart';
import '../models/entry.dart';
import '../money_format.dart';

/// Renders entries as CSV.
String entriesToCsv(
  Iterable<Entry> entries, {
  required Map<String, String> memberNames,
  required Map<String, Currency> currencies,
  Map<String, String> categoryNames = const {},
}) {
  final buffer = StringBuffer()
    ..writeln(
      _row([
        'date',
        'kind',
        'description',
        'category',
        'currency',
        'amount',
        'paid_by',
        'shares',
        'notes',
      ]),
    );

  String name(String memberId) => memberNames[memberId] ?? memberId;

  String money(String code, int minor) {
    final currency = currencies[code];
    return currency == null ? '$minor' : currency.formatPlain(minor);
  }

  for (final entry in entries) {
    if (entry.isDeleted) continue;

    buffer.writeln(
      _row([
        calendarDate(entry.row.entryDate),
        entry.row.kind.name,
        entry.row.description,
        entry.row.categoryId == null
            ? ''
            : categoryNames[entry.row.categoryId] ?? '',
        entry.row.currency,
        money(entry.row.currency, entry.row.amountMinor),
        [
          for (final payer in entry.payers)
            '${name(payer.memberId)}: '
                '${money(entry.row.currency, payer.amountMinor)}',
        ].join('; '),
        [
          for (final share in entry.shares)
            '${name(share.memberId)}: '
                '${money(entry.row.currency, share.amountMinor)}',
        ].join('; '),
        entry.row.notes ?? '',
      ]),
    );
  }

  return buffer.toString();
}

String _row(List<String> fields) => fields.map(_escape).join(',');

/// Characters that make a spreadsheet treat a cell as a formula rather than
/// text. Tab and carriage return are here because Excel strips leading
/// whitespace before deciding, so they smuggle the next character into first
/// position.
final RegExp _formulaLead = RegExp(r'^[=+\-@\t\r]');

/// RFC 4180 escaping, plus formula neutralisation.
String _escape(String value) {
  final safe = _formulaLead.hasMatch(value) ? "'$value" : value;
  if (!safe.contains(RegExp('[",\n\r]'))) return safe;
  return '"${safe.replaceAll('"', '""')}"';
}
