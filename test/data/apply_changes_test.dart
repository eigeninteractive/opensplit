import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/apply_changes.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:test/test.dart';

import '../harness.dart';

/// A null on a page is a value, not an absence: restoring, rejoining and
/// clearing all arrive as one, and a local copy that kept the old value would
/// disagree with every other device for good.
void main() {
  late AppDatabase db;
  final at = DateTime.utc(2026, 9, 27);

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  api.Group group({String id = 'g', DateTime? archivedAt, int seq = 1}) =>
      api.Group(
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
        archivedAt: archivedAt,
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

  test('a restore, a rejoin and a cleared handle all land', () async {
    await applyGroupChanges(
      db,
      page(
        seq: 1,
        group: group(archivedAt: at),
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

    final stored = await db.select(db.groups).getSingle();
    final ravi = await db.select(db.members).getSingle();
    final account = await db.select(db.profiles).getSingle();
    expect(stored.archivedAt, isNull, reason: 'the group was restored');
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
