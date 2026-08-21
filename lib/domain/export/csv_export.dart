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
            '${name(payer.memberId)}: ${money(entry.currency, payer.amountMinor)}',
        ].join('; '),
        [
          for (final share in entry.shares)
            '${name(share.memberId)}: ${money(entry.currency, share.amountMinor)}',
        ].join('; '),
        entry.notes ?? '',
      ]),
    );
  }

  return buffer.toString();
}

String _row(List<String> fields) => fields.map(_escape).join(',');

/// RFC 4180 escaping.
///
/// Descriptions routinely contain commas, and notes contain newlines; a naïve
/// join produces a file that opens misaligned and is then silently trusted.
String _escape(String value) {
  if (!value.contains(RegExp('[",\n\r]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
