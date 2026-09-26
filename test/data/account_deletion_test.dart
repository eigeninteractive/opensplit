import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:test/test.dart';

import '../harness.dart';

/// What the confirmation dialog tells somebody before they delete an account.
void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;

  const ravi = 'ravi-account';
  const priya = 'priya-account';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    await seedReferenceData(db);
    groups = DriftGroupRepository(db);
  });
  tearDown(() => db.close());

  test('a group nobody else has an account in counts as solo', () async {
    await groups.createGroup(
      name: 'Just me',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: ravi,
    );

    expect(await groups.membershipBreakdown(ravi), (solo: 1, shared: 0));
  });

  test('a placeholder does not make a group shared', () async {
    final created = await groups.createGroup(
      name: 'Beach trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: ravi,
    );
    await groups.addMember(created.group.id, displayName: 'Arun');

    expect(
      await groups.membershipBreakdown(ravi),
      (solo: 1, shared: 0),
      reason:
          'nobody can sign in as a placeholder, so this group still has '
          'no reader left once Ravi goes',
    );
  });

  test('one other account is enough to make it shared', () async {
    final created = await groups.createGroup(
      name: 'Flat 4B',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: ravi,
    );
    await groups.addMember(
      created.group.id,
      displayName: 'Priya',
      profileId: priya,
    );

    expect(await groups.membershipBreakdown(ravi), (solo: 0, shared: 1));
  });

  test('groups this account is not in are not counted at all', () async {
    await groups.createGroup(
      name: 'Someone else\'s',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Priya',
      creatorProfileId: priya,
    );

    expect(await groups.membershipBreakdown(ravi), (solo: 0, shared: 0));
  });

  // The other half of "a group outlives its creator", and the reason it is no
  // longer a question about nulls.
  group('a group whose creator deleted their account', () {
    test('still says who started it, because that is a member', () async {
      final created = await groups.createGroup(
        name: 'Offline',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
      );

      // Created with no account at all, which used to leave this null -- the
      // column held a profile id, and there was no profile.
      expect(created.group.createdBy, created.creator.id);
      final stored = await groups.watchGroup(created.group.id).first;
      expect(stored?.createdBy, created.creator.id);

      // And it resolves, which is the whole point of moving it: the id can be
      // looked up in this group's own members and yields a name to show.
      final members = await groups.watchMembers(created.group.id).first;
      expect(
        members.firstWhere((m) => m.id == stored?.createdBy).displayName,
        'Ravi',
      );
    });
  });
}
