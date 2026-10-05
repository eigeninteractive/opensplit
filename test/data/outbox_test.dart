import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/tables.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/group_event.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

import '../harness.dart';

/// The outbox is a set of dirty rows, not a log, and everything a device does
/// is on its own screen before any server hears of it.
void main() {
  late AppDatabase db;
  late OutboxQueue outbox;

  setUp(() async {
    db = await testDatabase();
    outbox = OutboxQueue(db);
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  test('old failures cannot back off or remove a fresh edit', () async {
    await outbox.enqueue(OutboxTarget.group, 'queued-group');
    final old = (await outbox.due()).single;
    await outbox.enqueue(OutboxTarget.group, 'queued-group');

    await outbox.fail(old, 'refused', permanent: true);
    await outbox.complete(old);

    final current = (await outbox.due()).single;
    expect(current.revision, isNot(old.revision));
    expect(current.attempts, 0);
    expect(current.deadLetteredAt, isNull);
  });

  test('backed-off parents block dependants until the retry is due', () async {
    var now = DateTime.utc(2026, 8, 28);
    final clocked = OutboxQueue(db, clock: () => now);
    addTearDown(clocked.dispose);
    await clocked.enqueue(OutboxTarget.group, 'g1');
    await clocked.enqueue(OutboxTarget.member, 'm1');
    await clocked.enqueue(OutboxTarget.entry, 'e1');
    await clocked.fail((await clocked.due()).first, 'offline');

    // The member and entry have no deadline, but cannot overtake the group.
    expect(await clocked.due(), isEmpty);
    expect(await clocked.nextAttemptAt(), now.add(const Duration(seconds: 2)));

    now = now.add(const Duration(seconds: 2));
    final due = await clocked.due();
    expect(due.map((row) => row.targetId), ['g1', 'm1', 'e1']);
    await clocked.complete(due[0]);
    await clocked.fail(due[1], 'offline');
    expect(await clocked.due(), isEmpty);

    now = now.add(const Duration(seconds: 2));
    expect((await clocked.due()).map((row) => row.targetId), ['m1', 'e1']);
  });

  test('dead letters have no automatic retry deadline', () async {
    await outbox.enqueue(OutboxTarget.group, 'g1');
    expect(await outbox.nextAttemptAt(), isNotNull);
    await outbox.fail((await outbox.due()).single, 'refused', permanent: true);
    expect(await outbox.nextAttemptAt(), isNull);
  });

  group('the order changes are pushed in', () {
    late DriftGroupRepository groups;
    late DriftEntryRepository entries;

    setUp(() {
      groups = DriftGroupRepository(db, outbox: outbox);
      entries = DriftEntryRepository(db, outbox: outbox);
    });

    Future<List<OutboxTarget>> order() async => [
      for (final item in await outbox.due()) item.target,
    ];

    /// The server checks a removal against the balances it holds, so the
    /// settlement that makes it possible has to arrive first.
    test('is the order they were made in', () async {
      final made = await groups.createGroup(
        name: 'Goa',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
      );
      final priya = await groups.addMember(made.group.id, displayName: 'Priya');
      await _acknowledge(db);

      await groups.renameMember(priya.id, 'Priya S');
      await entries.create(
        _draft(made.group.id, made.creator.id, priya.id),
        createdBy: made.creator.id,
      );
      await groups.removeMember(priya.id);

      expect(await order(), [OutboxTarget.entry, OutboxTarget.member]);
    });

    /// Until the server has a row, everything after its creation may name it.
    test(
      'keeps a row the server has never seen where it was created',
      () async {
        final made = await groups.createGroup(
          name: 'Goa',
          defaultCurrency: 'INR',
          creatorDisplayName: 'Ravi',
        );
        final priya = await groups.addMember(
          made.group.id,
          displayName: 'Priya',
        );
        await entries.create(
          _draft(made.group.id, made.creator.id, priya.id),
          createdBy: made.creator.id,
        );
        await groups.renameMember(priya.id, 'Priya S');

        expect(await order(), [
          OutboxTarget.group,
          OutboxTarget.member,
          OutboxTarget.member,
          OutboxTarget.entry,
        ]);
      },
    );
  });

  test('every enqueue announces itself', () async {
    final announced = <void>[];
    final subscription = outbox.queued.listen(announced.add);
    addTearDown(subscription.cancel);

    await outbox.enqueue(OutboxTarget.entry, 'e1');
    await outbox.enqueue(OutboxTarget.group, 'g1');
    await pumpEventQueue();

    expect(announced, hasLength(2));
  });

  test('re-dirtying a row does clear its retry state', () async {
    await outbox.enqueue(OutboxTarget.group, 'g1');
    await outbox.fail((await outbox.due()).single, 'refused', permanent: true);
    expect(await outbox.deadLetters(), hasLength(1));

    // Whatever the server objected to may be exactly what this edit changed.
    await outbox.enqueue(OutboxTarget.group, 'g1');
    expect(await outbox.deadLetters(), isEmpty);
    expect(await outbox.due(), hasLength(1));
  });

  test('an expense is in the feed with no server in sight', () async {
    final groups = DriftGroupRepository(db, outbox: outbox);
    final entries = DriftEntryRepository(db, outbox: outbox);
    final created = await groups.createGroup(
      name: 'Goa Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: testAccountId,
    );
    final ravi = created.creator.id;
    await entries.create(
      EntryDraft(
        groupId: created.group.id,
        currency: 'INR',
        amountMinor: 120000,
        description: 'Dinner',
        split: EqualSplit([ravi]),
        payerAmounts: {ravi: 120000},
      ),
      createdBy: ravi,
    );

    final feed = (await DriftActivityRepository(
      db,
    ).watchGroup(created.group.id).first).whereType<EntryChanged>();
    expect(feed.single.kind, EntryEventKind.created);
    expect(feed.single.actorId, ravi);
    expect(feed.single.isProvisional, isTrue);
  });
}

/// Marks every row as one the server has, and empties the outbox, as a
/// successful push would.
Future<void> _acknowledge(AppDatabase db) async {
  await db.customStatement('UPDATE groups SET seq = 1');
  await db.customStatement('UPDATE members SET seq = 1');
  await db.customStatement('UPDATE entries SET seq = 1');
  await db.delete(db.outbox).go();
}

EntryDraft _draft(String groupId, String payer, String payee) =>
    EntryDraft.settlement(
      groupId: groupId,
      currency: 'INR',
      amountMinor: 500,
      fromMemberId: payer,
      toMemberId: payee,
    );
