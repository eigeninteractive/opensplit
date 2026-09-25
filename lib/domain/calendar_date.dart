/// An expense happens on a day, not at an instant.
///
/// A day is held as a `DateTime` at UTC midnight and written `yyyy-MM-dd`, as
/// on the wire. [calendarDate] reads the value's own fields rather than
/// converting through a time zone, so it gives the same day for a value at
/// local midnight too; converting first would move it to the previous day
/// anywhere east of Greenwich.
library;

String calendarDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseCalendarDate(String day) => DateTime.parse('${day}T00:00:00Z');

/// The day [instant] falls on where it happened, at UTC midnight.
DateTime calendarDay(DateTime instant) =>
    DateTime.utc(instant.year, instant.month, instant.day);
