import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/wire.dart';
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

  // The other half of "a group outlives its creator". delete_account() sets
  // groups.created_by to null on the server, so a group in that state arrives
  // here on the next pull and has to survive being parsed, stored and pushed
  // back — with null meaning null the whole way, rather than an empty string
  // standing in for it somewhere in the middle.
  group('a group whose creator deleted their account', () {
    test('parses with no creator', () {
      final parsed = groupFromJson({
        'id': 'g1',
        'name': 'Flat 4B',
        'default_currency': 'INR',
        'created_by': null,
        'created_at': '2026-08-26T00:00:00Z',
      });

      expect(parsed.createdBy, isNull);
    });

    test('goes back out as null, not as a placeholder value', () {
      final parsed = groupFromJson({
        'id': 'g1',
        'name': 'Flat 4B',
        'default_currency': 'INR',
        'created_by': null,
        'created_at': '2026-08-26T00:00:00Z',
      });

      expect(groupToJson(parsed)['created_by'], isNull);
    });

    test('a group created without an account has no creator either', () async {
      final created = await groups.createGroup(
        name: 'Offline',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
      );

      // What this guards: the row used to be written with the owner's *member*
      // id in a column that holds profile ids, while the Group object returned
      // from the same call carried an empty string. Two different stand-ins for
      // the same absent value, neither of which was the value.
      expect(created.group.createdBy, isNull);
      final stored = await groups.watchGroup(created.group.id).first;
      expect(stored?.createdBy, isNull);
    });
  });
}
