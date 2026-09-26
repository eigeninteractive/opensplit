import 'package:intl/intl.dart';

import '../domain/models/entry.dart';

// Money formatting, kept in the domain so screens and notification text can
// never diverge.
export '../domain/money_format.dart';

/// When an expense happened, for a list line: its day, and its time on this
/// device's clock when known.
String formatWhen(Entry entry) {
  final day = DateFormat.MMMd().format(entry.entryDate);
  final at = entry.occurredAt;
  return at == null ? day : '$day, ${DateFormat.jm().format(at.toLocal())}';
}
