import 'dart:async';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import '../harness.dart';

void main() {
  late AppDatabase db;
  late DriftEntryRepository entries;
  late String groupId;
  late String ana;
  late String maya;

  setUp(() async {
    db = await testDatabase();
    entries = DriftEntryRepository(db);
    final groups = DriftGroupRepository(db);
    final created = await groups.createGroup(
      name: 'Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ana',
    );
    groupId = created.group.id;
    ana = created.creator.id;
    maya = (await groups.addMember(groupId, displayName: 'Maya')).id;
  });
  tearDown(() => db.close());

  EntryDraft expense(
    String description, {
    String currency = 'INR',
    String? notes,
  }) => EntryDraft(
    groupId: groupId,
    currency: currency,
    amountMinor: 10000,
    description: description,
    notes: notes,
    split: EqualSplit([ana, maya]),
    payerAmounts: {ana: 10000},
  );

  test(
    'search spans currencies and payments, excludes other groups and deleted rows',
    () async {
      final coffee = await entries.create(expense('Coffee'), createdBy: ana);
      final tokyo = await entries.create(
        expense('Coffee in Tokyo', currency: 'JPY'),
        createdBy: ana,
      );
      final payment = await entries.create(
        EntryDraft.settlement(
          groupId: groupId,
          currency: 'INR',
          amountMinor: 5000,
          fromMemberId: maya,
          toMemberId: ana,
          notes: 'Paid back for coffee',
        ),
        createdBy: maya,
      );
      final deleted = await entries.create(
        expense('Coffee deleted'),
        createdBy: ana,
      );
      await entries.delete(deleted.id, actorId: ana);
      final other = await DriftGroupRepository(db).createGroup(
        name: 'Other',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ana',
      );
      await entries.create(
        EntryDraft(
          groupId: other.group.id,
          currency: 'INR',
          amountMinor: 5000,
          description: 'Coffee elsewhere',
          split: EqualSplit([other.creator.id]),
          payerAmounts: {other.creator.id: 5000},
        ),
        createdBy: other.creator.id,
      );

      expect(
        (await entries.search(groupId, 'COF').first).map((entry) => entry.id),
        unorderedEquals([coffee.id, tokyo.id, payment.id]),
      );
      expect(
        (await entries.search(groupId, 'back cof').first).single.id,
        payment.id,
      );
      expect(await entries.search(groupId, '   ').first, isEmpty);
      for (final text in ['"', '*', 'NEAR(', 'a AND']) {
        await expectLater(entries.search(groupId, text).first, completes);
      }
    },
  );

  test('open search reacts to inserts, edited notes, and deletion', () async {
    final pending = StreamIterator<List<Entry>>(entries.search(groupId, 'cof'));
    addTearDown(pending.cancel);
    Future<List<Entry>> next() async {
      expect(await pending.moveNext(), isTrue);
      return pending.current;
    }

    expect(await next(), isEmpty);
    final row = await entries.create(
      expense('Dinner', notes: 'Coffee included'),
      createdBy: ana,
    );
    expect((await next()).single.id, row.id);
    await entries.update(
      row.id,
      expense('Dinner', notes: 'Tea included'),
      actorId: ana,
    );
    expect(await next(), isEmpty);
    await entries.update(
      row.id,
      expense('Dinner', notes: 'Coffee included'),
      actorId: ana,
    );
    expect((await next()).single.id, row.id);
    await entries.delete(row.id, actorId: ana);
    expect(await next(), isEmpty);
  });
}
