import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/sync/wire.dart';
import 'package:opensplit/domain/calendar_date.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

import '../harness.dart';
import 'package:opensplit_api/opensplit_api.dart' show Payer, Share;

void main() {
  group('updates', () {
    // Null is a value in an update (restore, rejoin, clear), so it has to be
    // on the wire rather than dropped.
    test('restoring a group sends archivedAt: null', () {
      final creator = Member(
        id: 'm',
        groupId: 'g',
        displayName: 'Ravi',
        joinedAt: DateTime.utc(2026),
      );
      final group = Group(
        id: 'g',
        name: 'Goa',
        defaultCurrency: 'INR',
        isDirect: false,
        simplifyDebts: true,
        createdAt: DateTime.utc(2026),
      );
      expect(group.toInput(creator).toJson(), containsPair('archivedAt', null));
    });

    test('rejoining and clearing a handle send their nulls', () {
      final member = Member(
        id: 'm',
        groupId: 'g',
        displayName: 'Priya',
        joinedAt: DateTime.utc(2026),
      );
      expect(
        member.toInput().toJson(),
        allOf(containsPair('leftAt', null), containsPair('upiVpa', null)),
      );
    });
  });

  test('when and where an expense happened survive the wire', () {
    final input = Entry(
      EntryRow(
        id: 'e',
        groupId: 'g',
        kind: api.EntryKind.expense,
        description: 'Snack',
        currency: 'INR',
        amountMinor: 100,
        entryDate: DateTime.utc(2026, 9, 24),
        occurredAt: DateTime.utc(2026, 9, 23, 19, 30),
        timeZone: 'Asia/Kolkata',
        splitKind: api.SplitKind.equal,
        createdBy: 'm',
        createdAt: DateTime.utc(2026, 9, 23, 19, 31),
      ),
      payers: [Payer(memberId: 'm', amountMinor: 100)],
      shares: [Share(memberId: 'm', amountMinor: 100, weightMicros: null)],
    ).toInput();
    final json = input.toJson();
    expect(json, containsPair('entryDate', '2026-09-24'));
    expect(json, containsPair('timeZone', 'Asia/Kolkata'));
    // The write is the whole row: a live expense says so, which is how a
    // restore reaches the server.
    expect(json, containsPair('deletedAt', null));
    expect(
      api.EntryInput.fromJson(json).occurredAt,
      DateTime.utc(2026, 9, 23, 19, 30),
    );
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
      api.EventKind kind, {
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
            group: Value(
              api.GroupEventPayload(name: 'Goa', previousName: null),
            ),
            seq: Value(seq),
            ordinal: Value(ordinal),
            isProvisional: Value(provisional),
          ),
        );

    test('reads in (seq, ordinal) order, not by id', () async {
      // Ids sort the opposite way to the order the change recorded them in.
      await line('b', api.EventKind.groupRenamed, seq: 4, ordinal: 0);
      await line('a', api.EventKind.groupArchived, seq: 4, ordinal: 1);
      await line('z', api.EventKind.groupRenamed, seq: 3, ordinal: 0);
      await line('p', api.EventKind.groupRestored, provisional: true);

      final feed = await DriftActivityRepository(db).watchGroup('g').first;
      expect([for (final event in feed) event.id], ['p', 'a', 'b', 'z']);
    });
  });
}
