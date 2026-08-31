import 'package:drift/native.dart';
import 'package:opensplit/application/entry_notification.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_currency_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

/// The composer both push paths use.
///
/// It exists as its own function so that the app and the background isolate —
/// which share no memory, no provider container and no open database — cannot
/// end up with two answers to "what does this expense say". These tests are
/// what makes that claim checkable: the background isolate itself cannot be
/// exercised from a test, but everything in it that decides wording is here.
void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;
  late DriftEntryRepository entries;
  late DriftCurrencyRepository currencies;
  late DriftActivityRepository activity;
  late DriftProfileRepository profiles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = DriftGroupRepository(db);
    entries = DriftEntryRepository(db);
    currencies = DriftCurrencyRepository(db);
    activity = DriftActivityRepository(db);
    profiles = DriftProfileRepository(db);
  });

  tearDown(() => db.close());

  Future<({String groupId, String ravi, String priya})> seed() async {
    final created = await groups.createGroup(
      name: 'Goa Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: 'profile-ravi',
    );
    final priya = await groups.addMember(
      created.group.id,
      displayName: 'Priya',
      profileId: 'profile-priya',
    );
    return (
      groupId: created.group.id,
      ravi: created.creator.id,
      priya: priya.id,
    );
  }

  Future<String> addExpense(
    ({String groupId, String ravi, String priya}) g, {
    required String description,
    int amountMinor = 240000,
  }) async {
    final entry = await entries.create(
      EntryDraft(
        groupId: g.groupId,
        currency: 'INR',
        amountMinor: amountMinor,
        description: description,
        split: EqualSplit([g.ravi, g.priya]),
        payerAmounts: {g.ravi: amountMinor},
      ),
      createdBy: g.ravi,
    );
    return entry.id;
  }

  test('names the group, the author and the recipient own share', () async {
    final g = await seed();
    final entryId = await addExpense(g, description: 'Dinner at Toit');

    final text = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      groupId: g.groupId,
      entryId: entryId,
    );

    expect(text, isNotNull);
    expect(text!.title, 'Goa Trip');
    expect(text.body, contains('Ravi'));
    expect(text.body, contains('Dinner at Toit'));
    // The recipient's own share, at the currency's own precision, from the
    // formatter the screens use.
    expect(text.body, contains('₹1,200.00'));
  });

  test('uses a claimed profile name instead of the placeholder', () async {
    final g = await seed();
    await profiles.upsert(
      const Profile(id: 'profile-ravi', displayName: 'Ravi D'),
    );
    final entryId = await addExpense(g, description: 'Dinner');

    final text = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      groupId: g.groupId,
      entryId: entryId,
    );

    expect(text?.body, contains('Ravi D'));
  });

  test('the share shown is the reader own, not the author own', () async {
    final g = await seed();
    final entryId = await addExpense(g, description: 'Dinner');

    final forRavi = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-ravi',
      groupId: g.groupId,
      entryId: entryId,
    );
    final forPriya = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      groupId: g.groupId,
      entryId: entryId,
    );

    // Same expense, same total, and both are told their own half.
    expect(forRavi!.body, contains('₹1,200.00'));
    expect(forPriya!.body, contains('₹1,200.00'));
    expect(forRavi.body, contains('₹2,400.00'));
  });

  test('somebody outside the split is told, without a share of zero', () async {
    final g = await seed();
    final entryId = await addExpense(g, description: 'Dinner');

    final text = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      // Nobody this device knows: a member of the group who is not on the
      // expense, or a profile that has not been reconciled yet.
      myProfileId: 'profile-nobody',
      groupId: g.groupId,
      entryId: entryId,
    );

    expect(text!.body, contains('₹2,400.00'));
    expect(
      text.body,
      isNot(contains('Your share')),
      reason: 'claiming a share of zero reads as a bug',
    );
  });

  test('an entry the sync could not fetch produces nothing at all', () async {
    final g = await seed();

    final text = await composeEntryNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      groupId: g.groupId,
      entryId: 'an-id-this-device-has-never-seen',
    );

    // Rather than a banner about an expense nobody can open.
    expect(text, isNull);
  });

  test('the route opens the group, which owns refresh', () {
    expect(groupNotificationRoute('g1'), '/g/g1');
  });
}
