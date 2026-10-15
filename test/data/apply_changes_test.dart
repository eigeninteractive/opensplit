import 'package:drift/drift.dart' show Value;
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/local/tables.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/data/sync/apply_changes.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

import '../harness.dart';

/// A null on a page is a value, not an absence: rejoining and
/// clearing all arrive as one, and a local copy that kept the old value would
/// disagree with every other device for good.
void main() {
  late AppDatabase db;
  final at = DateTime.utc(2026, 9, 27);

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  api.Group group({String id = 'g', int seq = 1}) => api.Group(
    avatarKind: api.AvatarKind.initials,
    avatarColor: null,
    avatarEmoji: null,
    avatarIcon: null,
    avatarPhoto: null,
    coverKind: api.CoverKind.generated,
    coverPhoto: null,
    id: id,
    name: 'Goa',
    defaultCurrency: 'INR',
    isDirect: false,
    simplifyDebts: true,
    createdBy: 'm',
    createdAt: at,
    updatedAt: at,
    lastActivityAt: at,
    seq: seq,
  );

  api.Member member({String? upiVpa, DateTime? leftAt, int seq = 1}) =>
      api.Member(
        id: 'm',
        profileId: 'p',
        displayName: 'Ravi',
        upiVpa: upiVpa,
        joinedAt: at,
        leftAt: leftAt,
        updatedAt: at,
        seq: seq,
      );

  api.Profile profile({String? upiVpa, required int version}) => api.Profile(
    avatarKind: api.AvatarKind.initials,
    avatarColor: null,
    avatarEmoji: null,
    avatarIcon: null,
    avatarPhoto: null,
    id: 'p',
    displayName: 'Ravi',
    upiVpa: upiVpa,
    updatedAt: at,
    deletedAt: null,
    version: version,
  );

  api.ChangePage page({
    required int seq,
    required api.Group group,
    required api.Member member,
    required api.Profile profile,
    List<api.Entry> entries = const [],
  }) => api.ChangePage(
    groupId: group.id,
    seq: seq,
    hasMore: false,
    group: group,
    members: [member],
    profiles: [profile],
    entries: entries,
    events: const [],
    purgedAt: null,
  );

  test('purging clears dependent rows and queued edits atomically', () async {
    final queue = OutboxQueue(db);
    addTearDown(queue.dispose);
    final groups = DriftGroupRepository(db, outbox: queue);
    final entries = DriftEntryRepository(db, outbox: queue);
    final made = await groups.createGroup(
      name: 'Deleted',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
    );
    final retained = await groups.createGroup(
      name: 'Retained',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Priya',
    );
    final entry = await entries.create(
      EntryDraft(
        groupId: made.group.id,
        currency: 'INR',
        amountMinor: 100,
        description: 'Dinner',
        split: EqualSplit([made.creator.id]),
        payerAmounts: {made.creator.id: 100},
      ),
      createdBy: made.creator.id,
    );
    await db
        .into(db.groupCursors)
        .insert(
          GroupCursorsCompanion.insert(
            groupId: made.group.id,
            seq: const Value(1),
          ),
        );
    final tombstone = api.ChangePage(
      groupId: made.group.id,
      seq: 2,
      hasMore: false,
      group: null,
      members: const [],
      profiles: const [],
      entries: const [],
      events: const [],
      purgedAt: at,
    );
    await db.customStatement(
      "CREATE TRIGGER reject_removal BEFORE DELETE ON groups BEGIN SELECT RAISE(ABORT, 'test rollback'); END;",
    );
    await expectLater(
      applyGroupChanges(db, tombstone, now: at),
      throwsA(anything),
    );
    expect(await groups.getGroup(made.group.id), isNotNull);
    expect(await queue.unsentIds(OutboxTarget.entry), contains(entry.id));
    await db.customStatement('DROP TRIGGER reject_removal');
    await applyGroupChanges(db, tombstone, now: at);
    expect(await groups.getGroup(made.group.id), isNull);
    expect(await entries.getEntry(entry.id), isNull);
    expect(await db.select(db.entryPayers).get(), isEmpty);
    expect(await db.select(db.entryShares).get(), isEmpty);
    expect(await db.select(db.groupCursors).get(), isEmpty);
    expect(
      (await db.select(db.groupEvents).get()).where(
        (e) => e.groupId == made.group.id,
      ),
      isEmpty,
    );
    expect(await queue.unsentIds(OutboxTarget.entry), isEmpty);
    expect(await queue.unsentIds(OutboxTarget.group), [retained.group.id]);
    expect(await groups.getGroup(retained.group.id), isNotNull);
  });

  test('a rejoin and a cleared handle both land', () async {
    await applyGroupChanges(
      db,
      page(
        seq: 1,
        group: group(),
        member: member(upiVpa: 'ravi@okaxis', leftAt: at),
        profile: profile(upiVpa: 'ravi@okaxis', version: 1),
      ),
      now: at,
    );

    await applyGroupChanges(
      db,
      page(
        seq: 2,
        group: group(seq: 2),
        member: member(seq: 2),
        profile: profile(version: 2),
      ),
      now: at,
    );

    final ravi = await db.select(db.members).getSingle();
    final account = await db.select(db.profiles).getSingle();
    expect(ravi.leftAt, isNull, reason: 'Ravi rejoined');
    expect(ravi.upiVpa, isNull, reason: 'the group handle was cleared');
    expect(account.upiVpa, isNull, reason: 'the account handle was cleared');
  });

  /// Ids are minted on devices and checked by each group's server only within
  /// that group, so another group can name a row this device already holds.
  test('a row of another group is neither moved nor named', () async {
    await applyGroupChanges(
      db,
      page(
        seq: 1,
        group: group(),
        member: member(),
        profile: profile(version: 1),
      ),
      now: at,
    );

    final elsewhere = page(
      seq: 1,
      group: group(id: 'h'),
      member: member(),
      profile: profile(version: 1),
      entries: [
        api.Entry(
          id: 'e',
          kind: api.EntryKind.expense,
          description: 'Taken',
          categoryId: null,
          currency: 'INR',
          amountMinor: 100,
          entryDate: '2026-09-27',
          occurredAt: null,
          timeZone: null,
          splitKind: api.SplitKind.exact,
          fxRate: null,
          fxSource: null,
          fxAt: null,
          notes: null,
          createdBy: 'm',
          createdAt: at,
          updatedAt: at,
          deletedAt: null,
          seq: 1,
          payers: [api.Payer(memberId: 'm', amountMinor: 100)],
          shares: [
            api.Share(memberId: 'm', amountMinor: 100, weightMicros: null),
          ],
        ),
      ],
    );
    await applyGroupChanges(db, elsewhere, now: at);

    final ravi = await db.select(db.members).getSingle();
    expect(ravi.groupId, 'g', reason: 'still in the group it came from');
    expect(await db.select(db.entries).get(), isEmpty);
    final cursor = await (db.select(
      db.groupCursors,
    )..where((t) => t.groupId.equals('h'))).getSingle();
    expect(cursor.seq, 1, reason: 'the rest of the page still lands');
  });
}
