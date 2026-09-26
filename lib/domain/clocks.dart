/// Reading a moment on the clock where it happened.
///
/// An expense can carry an instant and the IANA zone it happened in. Shown
/// anywhere, it reads as that place's time: dinner in Bangkok is 9:40 pm on
/// every phone, labelled `+07` on a phone that is not in Bangkok.
///
/// This device's own zone needs nothing but `DateTime`'s local time. Any other
/// zone needs the IANA database from `package:timezone`, which is loaded on
/// first use through a deferred import, so the web app's first download does
/// not carry it. `latest_all`, because it keeps the old aliases
/// (`Asia/Calcutta`) that some phones still report.
library;

import 'package:timezone/data/latest_all.dart' deferred as database;
import 'package:timezone/timezone.dart' as tz;

Future<void>? _loading;

/// Loads the time zone database once. A failed load (on the web, offline
/// before the file was ever fetched) is retried on the next call.
Future<void> loadTimeZoneDatabase() => _loading ??= () async {
  try {
    await database.loadLibrary();
    database.initializeTimeZones();
  } catch (_) {
    _loading = null;
    rethrow;
  }
}();

/// A moment: the instant, and the zone it is read in.
typedef Moment = ({DateTime at, String zone});

class Clocks {
  const Clocks({required this.device});

  /// This device's IANA zone, or null when the platform would not say.
  final String? device;

  /// What the clock read at [instant] in [zone].
  ///
  /// This device's local time when [zone] is this device's, or when the
  /// database cannot read it yet.
  DateTime wallClock(DateTime instant, String zone) {
    final location = _location(zone);
    return location == null
        ? instant.toLocal()
        : tz.TZDateTime.from(instant, location);
  }

  /// [zone]'s short name at [instant] (`IST`, `+07`) when its clock reads
  /// differently from this device's; null when they agree.
  String? foreignLabel(DateTime instant, String zone) {
    final location = _location(zone);
    if (location == null) return null;
    final there = tz.TZDateTime.from(instant, location);
    return there.timeZoneOffset == instant.toLocal().timeZoneOffset
        ? null
        : there.timeZoneName;
  }

  /// The moment [hour]:[minute] on [day] is on the clock in [zone].
  ///
  /// Falls back to this device's zone when [zone] cannot be read, so the
  /// moment and its zone always agree. Null when neither can be.
  Moment? moment(
    DateTime day, {
    required int hour,
    required int minute,
    required String? zone,
  }) {
    final location = zone == null ? null : _location(zone);
    if (location != null) {
      final at = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      );
      return (at: at.toUtc(), zone: zone!);
    }
    final here = device;
    if (here == null) return null;
    final at = DateTime(day.year, day.month, day.day, hour, minute);
    return (at: at.toUtc(), zone: here);
  }

  /// Null for this device's zone, which local time already reads.
  tz.Location? _location(String zone) {
    if (zone == device) return null;
    try {
      return tz.getLocation(zone);
    } on tz.LocationNotFoundException {
      return null;
    }
  }
}
