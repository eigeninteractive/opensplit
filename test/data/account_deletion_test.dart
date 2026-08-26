import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:test/test.dart';

/// What the confirmation dialog tells somebody before they delete an account.
///
/// The distinction it is drawing is the one people get wrong: a group nobody
/// else has an account in disappears with them, and a shared one does not. The
/// server makes the same distinction in delete_account(), and this is the
/// client's copy of it — see supabase/tests/07_account_deletion_test.sql.
void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;

  const ravi = 'ravi-account';
  const priya = 'priya-account';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = DriftGroupRepository(db);
  });
  tearDown(() => db.close());

  test('a group nobody else has an account in counts as solo', () async {
    await groups.createGroup(
      name: 'Just me',
      defaultCurrency: 'INR',
      ownerDisplayName: 'Ravi',
      ownerProfileId: ravi,
    );

    expect(await groups.membershipBreakdown(ravi), (solo: 1, shared: 0));
  });

  test('a placeholder does not make a group shared', () async {
    final created = await groups.createGroup(
      name: 'Beach trip',
      defaultCurrency: 'INR',
      ownerDisplayName: 'Ravi',
      ownerProfileId: ravi,
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
      ownerDisplayName: 'Ravi',
      ownerProfileId: ravi,
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
      ownerDisplayName: 'Priya',
      ownerProfileId: priya,
    );

    expect(await groups.membershipBreakdown(ravi), (solo: 0, shared: 0));
  });
}
