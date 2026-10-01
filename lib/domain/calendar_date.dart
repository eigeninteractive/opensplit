/// An expense happens on a day, not at an instant.
library;

import 'package:intl/intl.dart';

/// Fixed to `en_US` so no locale can swap in its own digits.
final _format = DateFormat('yyyy-MM-dd', 'en_US');

String calendarDate(DateTime day) => _format.format(day);

DateTime parseCalendarDate(String day) => _format.parseUtc(day);

/// The day [instant] falls on where it happened, at UTC midnight.
DateTime calendarDay(DateTime instant) =>
    DateTime.utc(instant.year, instant.month, instant.day);
