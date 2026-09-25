/// An expense happens on a day, not at an instant.
///
/// Dart has no date-only type, so a day is a `DateTime` at UTC midnight,
/// written `yyyy-MM-dd` on the wire and in the local database.
/// [calendarDate] formats the value's own fields rather than converting
/// through a time zone, so a value at local midnight gives the same day.
library;

import 'package:intl/intl.dart';

/// Fixed to `en_US` so no locale can swap in its own digits.
final _format = DateFormat('yyyy-MM-dd', 'en_US');

String calendarDate(DateTime day) => _format.format(day);

DateTime parseCalendarDate(String day) => _format.parseUtc(day);

/// The day [instant] falls on where it happened, at UTC midnight.
DateTime calendarDay(DateTime instant) =>
    DateTime.utc(instant.year, instant.month, instant.day);
