import 'package:intl/intl.dart';

import '../domain/clocks.dart';
import '../domain/models/entry.dart';

// Money formatting, kept in the domain so screens and notification text can
// never diverge.
export '../domain/money_format.dart';

/// When an expense happened, for a list line: its day, and when known the
/// time on the clock where it happened, labelled if that is not this
/// device's clock. Only the day until [clocks] can read other zones.
String formatWhen(Entry entry, Clocks? clocks) {
  final day = DateFormat.MMMd().format(entry.entryDate);
  final at = entry.occurredAt;
  final zone = entry.timeZone;
  if (at == null || zone == null || clocks == null) return day;
  return [
    '$day, ${DateFormat.jm().format(clocks.wallClock(at, zone))}',
    ?clocks.foreignLabel(at, zone),
  ].join(' ');
}
