import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/entry_writer.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:test/test.dart';

import '../harness.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    final now = DateTime.utc(2026, 9, 20);
    await db
        .into(db.groups)
        .insert(
          Group(
            id: 'g',
            name: 'Goa',
            defaultCurrency: 'INR',
            isDirect: false,
            simplifyDebts: true,
            createdAt: now,
          ),
        );
    await db
        .into(db.members)
        .insert(
          Member(id: 'm', groupId: 'g', displayName: 'Ravi', joinedAt: now),
        );
  });
  tearDown(() => db.close());

  Future<void> record(
    String description,
    DateTime day, {
    DateTime? at,
    required DateTime entered,
  }) => db.transaction(
    () => writeEntryInTransaction(
      db,
      Entry(
        id: description,
        groupId: 'g',
        kind: EntryKind.expense,
        description: description,
        currency: 'INR',
        amountMinor: 100,
        entryDate: day,
        occurredAt: at,
        timeZone: at == null ? null : 'Asia/Kolkata',
        splitKind: SplitKind.equal,
        payers: const [EntryPayer(memberId: 'm', amountMinor: 100)],
        shares: const [EntryShare(memberId: 'm', amountMinor: 100)],
        createdBy: 'm',
        createdAt: entered,
      ),
    ),
  );

  test('newest day first, and within a day the latest time first', () async {
    final today = DateTime.utc(2026, 9, 24);
    // Entered in the opposite order to when they happened, and the one with
    // no time entered last of all.
    await record(
      'Dinner',
      today,
      at: DateTime.utc(2026, 9, 24, 14),
      entered: DateTime.utc(2026, 9, 24, 15),
    );
    await record(
      'Lunch',
      today,
      at: DateTime.utc(2026, 9, 24, 7),
      entered: DateTime.utc(2026, 9, 24, 16),
    );
    await record('Snacks', today, entered: DateTime.utc(2026, 9, 24, 17));
    await record(
      'Yesterday',
      DateTime.utc(2026, 9, 23),
      at: DateTime.utc(2026, 9, 23, 18),
      entered: DateTime.utc(2026, 9, 24, 18),
    );

    final entries = await DriftEntryRepository(db).getEntries('g');
    expect(
      [for (final entry in entries) entry.description],
      ['Dinner', 'Lunch', 'Snacks', 'Yesterday'],
      reason: 'an expense with no time comes after that day\'s timed ones',
    );
  });
}
