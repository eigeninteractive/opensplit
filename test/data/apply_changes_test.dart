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

  api.Group group({DateTime? archivedAt, int seq = 1}) => api.Group(
    id: 'g',
    name: 'Goa',
    defaultCurrency: 'INR',
    isDirect: false,
    simplifyDebts: true,
    createdBy: 'm',
    createdAt: at,
    archivedAt: archivedAt,
    updatedAt: at,
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

  api.Profile profile({String? upiVpa, required DateTime updatedAt}) =>
      api.Profile(
        id: 'p',
        displayName: 'Ravi',
        upiVpa: upiVpa,
        updatedAt: updatedAt,
        deletedAt: null,
      );

  api.ChangePage page({
    required int seq,
    required api.Group group,
    required api.Member member,
    required api.Profile profile,
  }) => api.ChangePage(
    groupId: 'g',
    seq: seq,
    hasMore: false,
    group: group,
    members: [member],
    profiles: [profile],
    entries: const [],
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
        profile: profile(upiVpa: 'ravi@okaxis', updatedAt: at),
      ),
      now: at,
    );

    await applyGroupChanges(
      db,
      page(
        seq: 2,
        group: group(seq: 2),
        member: member(seq: 2),
        profile: profile(updatedAt: at.add(const Duration(minutes: 1))),
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
}
