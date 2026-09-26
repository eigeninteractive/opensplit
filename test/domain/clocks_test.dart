import 'package:opensplit/domain/calendar_date.dart';
import 'package:opensplit/domain/clocks.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(loadTimeZoneDatabase);

  // No device zone, so every zone is read through the database and nothing
  // depends on where the machine running the test is.
  const clocks = Clocks(device: null);

  test('1 a.m. in Goa is the previous evening in UTC, and still the 24th', () {
    final snack = clocks.moment(
      DateTime.utc(2026, 9, 24),
      hour: 1,
      minute: 0,
      zone: 'Asia/Kolkata',
    )!;
    expect(snack.at, DateTime.utc(2026, 9, 23, 19, 30));
    expect(snack.zone, 'Asia/Kolkata');

    final wall = clocks.wallClock(snack.at, snack.zone);
    expect((wall.hour, wall.minute), (1, 0));
    expect(calendarDate(wall), '2026-09-24');
  });

  test('daylight saving comes from the database, not a fixed offset', () {
    DateTime noonIn(int month) => clocks
        .moment(
          DateTime.utc(2026, month, 1),
          hour: 12,
          minute: 0,
          zone: 'America/New_York',
        )!
        .at;
    expect(noonIn(7), DateTime.utc(2026, 7, 1, 16));
    expect(noonIn(12), DateTime.utc(2026, 12, 1, 17));
  });

  test('old aliases some phones still report are understood', () {
    final at = DateTime.utc(2026, 9, 23, 19, 30);
    expect(clocks.wallClock(at, 'Asia/Calcutta').hour, 1);
  });

  test('another zone is labelled with its own short name', () {
    // Nobody runs this suite at UTC+14.
    expect(
      clocks.foreignLabel(DateTime.utc(2026, 9, 23), 'Pacific/Kiritimati'),
      '+14',
    );
  });

  test('a zone nobody knows falls back to this device, or to nothing', () {
    final day = DateTime.utc(2026, 9, 24);
    expect(
      clocks.moment(day, hour: 9, minute: 0, zone: 'Goa/Beach'),
      isNull,
      reason: 'no device zone to fall back to',
    );
    const here = Clocks(device: 'Etc/UTC');
    expect(
      here.moment(day, hour: 9, minute: 0, zone: 'Goa/Beach')?.zone,
      'Etc/UTC',
      reason: 'the moment and its zone must agree',
    );
  });
}
