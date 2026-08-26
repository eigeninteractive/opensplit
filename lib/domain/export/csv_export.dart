import '../models/currency.dart';
import '../models/entry.dart';

/// Renders entries as CSV.
///
/// Deliberately lossless in a way a net-per-person export is not: every payer
/// and every share is written out with its own amount, so the file can
/// reconstruct the ledger exactly rather than only its outcome. Exports that
/// collapse to "who owes what" cannot be re-imported without guessing, which is
/// precisely why importing from other apps is hard.
///
/// Amounts are written in major units at the currency's own precision, because
/// this is for spreadsheets and humans. The currency column is right beside it,
/// since a bare number is meaningless in a multi-currency group.
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
        entry.entryDate.toIso8601String().split('T').first,
        entry.kind.name,
        entry.description,
        entry.categoryId == null ? '' : categoryNames[entry.categoryId] ?? '',
        entry.currency,
        money(entry.currency, entry.amountMinor),
        [
          for (final payer in entry.payers)
            '${name(payer.memberId)}: '
                '${money(entry.currency, payer.amountMinor)}',
        ].join('; '),
        [
          for (final share in entry.shares)
            '${name(share.memberId)}: '
                '${money(entry.currency, share.amountMinor)}',
        ].join('; '),
        entry.notes ?? '',
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
///
/// Descriptions routinely contain commas, and notes contain newlines; a naïve
/// join produces a file that opens misaligned and is then silently trusted.
///
/// The leading apostrophe is the second half, and it guards against a person
/// rather than against punctuation. Every field here is free text somebody in
/// the group typed, and Excel, Sheets and LibreOffice all execute a cell
/// beginning `=`, `+`, `-` or `@`. So one member writes an expense called
/// `=HYPERLINK(...)`, another exports the group, and it runs on their machine
/// with their files. The apostrophe forces the cell to text and is not itself
/// displayed.
String _escape(String value) {
  final safe = _formulaLead.hasMatch(value) ? "'$value" : value;
  if (!safe.contains(RegExp('[",\n\r]'))) return safe;
  return '"${safe.replaceAll('"', '""')}"';
}
