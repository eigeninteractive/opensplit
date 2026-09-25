import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit/domain/calendar_date.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:test/test.dart';

import '../harness.dart';

void main() {
  group('patches', () {
    // The server reads an absent field as "leave it alone", and a generated
    // client drops a null optional field. So null has to be sent explicitly,
    // or restoring, rejoining and clearing a handle never reach the server.
    test('restoring a group sends archivedAt: null', () {
      final group = Group(
        id: 'g',
        name: 'Goa',
        defaultCurrency: 'INR',
        isDirect: false,
        simplifyDebts: true,
        createdAt: DateTime.utc(2026),
      );
      expect(group.toPatch().toJson(), containsPair('archivedAt', null));
    });

    test('rejoining and clearing a handle send their nulls', () {
      final member = Member(
        id: 'm',
        groupId: 'g',
        displayName: 'Priya',
        joinedAt: DateTime.utc(2026),
      );
      expect(
        member.toPatch().toJson(),
        allOf(containsPair('leftAt', null), containsPair('upiVpa', null)),
      );
    });
  });

  group('a calendar date', () {
    test('is the same day at local midnight as at UTC midnight', () {
      expect(calendarDate(DateTime(2026, 9, 23)), '2026-09-23');
      expect(calendarDate(DateTime.utc(2026, 9, 23)), '2026-09-23');
    });

    test('survives the wire in both directions', () {
      final day = parseCalendarDate('2026-09-23');
      expect(day, DateTime.utc(2026, 9, 23));
      expect(calendarDate(day), '2026-09-23');
    });
  });

  group('the activity feed', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await seedReferenceData(db);
      await db
          .into(db.groups)
          .insert(
            Group(
              id: 'g',
              name: 'Goa',
              defaultCurrency: 'INR',
              isDirect: false,
              simplifyDebts: true,
              createdAt: DateTime.utc(2026),
            ),
          );
    });
    tearDown(() => db.close());

    Future<void> line(
      String id,
      EventKind kind, {
      int? seq,
      int? ordinal,
      bool provisional = false,
    }) => db
        .into(db.groupEvents)
        .insert(
          GroupEventsCompanion.insert(
            id: id,
            groupId: 'g',
            // One change: every line shares its instant.
            createdAt: DateTime.utc(2026, 9, 23),
            kind: kind,
            payload: const {'name': 'Goa', 'previousName': null},
            seq: Value(seq),
            ordinal: Value(ordinal),
            isProvisional: Value(provisional),
          ),
        );

    test('reads in (seq, ordinal) order, not by id', () async {
      // Ids sort the opposite way to the order the change recorded them in.
      await line('b', EventKind.groupRenamed, seq: 4, ordinal: 0);
      await line('a', EventKind.groupArchived, seq: 4, ordinal: 1);
      await line('z', EventKind.groupRenamed, seq: 3, ordinal: 0);
      await line('p', EventKind.groupRestored, provisional: true);

      final feed = await DriftActivityRepository(db).watchGroup('g').first;
      expect([for (final event in feed) event.id], ['p', 'a', 'b', 'z']);
    });
  });
}
