import 'package:drift/native.dart';
import 'package:opensplit/application/entry_notification.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_activity_repository.dart';
import 'package:opensplit/data/repositories/drift_currency_repository.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/repositories/drift_profile_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit_api/opensplit_api.dart'
    show AvatarKind, PushData, PushKind;
import 'package:test/test.dart';

import '../harness.dart';

PushData _push(
  String groupId,
  PushKind kind,
  String subjectId, {
  String? currency,
}) => PushData(
  groupId: groupId,
  eventId: 'event',
  kind: kind,
  subjectId: subjectId,
  currency: currency,
);

/// The composer both push paths use.
void main() {
  late AppDatabase db;
  late DriftGroupRepository groups;
  late DriftEntryRepository entries;
  late DriftCurrencyRepository currencies;
  late DriftActivityRepository activity;
  late DriftProfileRepository profiles;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    await seedReferenceData(db);
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

    final text = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      push: _push(g.groupId, PushKind.entry, entryId),
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
      const Profile(
        avatarKind: AvatarKind.initials,
        id: 'profile-ravi',
        displayName: 'Ravi D',
      ),
    );
    final entryId = await addExpense(g, description: 'Dinner');

    final text = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      push: _push(g.groupId, PushKind.entry, entryId),
    );

    expect(text?.body, contains('Ravi D'));
  });

  test('the share shown is the reader own, not the author own', () async {
    final g = await seed();
    final entryId = await addExpense(g, description: 'Dinner');

    final forRavi = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-ravi',
      push: _push(g.groupId, PushKind.entry, entryId),
    );
    final forPriya = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      push: _push(g.groupId, PushKind.entry, entryId),
    );

    // Same expense, same total, and both are told their own half.
    expect(forRavi!.body, contains('₹1,200.00'));
    expect(forPriya!.body, contains('₹1,200.00'));
    expect(forRavi.body, contains('₹2,400.00'));
  });

  test('somebody outside the split is told, without a share of zero', () async {
    final g = await seed();
    final entryId = await addExpense(g, description: 'Dinner');

    final text = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      // Nobody this device knows: a member of the group who is not on the
      // expense, or a profile that has not been reconciled yet.
      myProfileId: 'profile-nobody',
      push: _push(g.groupId, PushKind.entry, entryId),
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

    final text = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      push: _push(
        g.groupId,
        PushKind.entry,
        'an-id-this-device-has-never-seen',
      ),
    );

    // Rather than a banner about an expense nobody can open.
    expect(text, isNull);
  });

  test('a reminder names who is asking and what this device owes', () async {
    final g = await seed();
    await addExpense(g, description: 'Dinner');

    final text = await composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: 'profile-priya',
      push: _push(g.groupId, PushKind.reminder, g.ravi, currency: 'INR'),
    );

    expect(text!.title, 'Goa Trip');
    expect(text.body, 'Ravi sent a reminder: you owe them ₹1,200.00.');
  });

  test('a weekly reminder uses the current balance on this device', () async {
    final g = await seed();
    await addExpense(g, description: 'Dinner');

    Future<({String title, String body})?> remind(String profileId) =>
        composeEventNotification(
          entries: entries,
          groups: groups,
          profiles: profiles,
          currencies: currencies,
          activity: activity,
          myProfileId: profileId,
          push: _push(g.groupId, PushKind.settlementNudge, g.groupId),
        );

    expect(await remind('profile-ravi'), isNull);
    expect(await remind('profile-priya'), (
      title: 'Goa Trip',
      body: 'You still have a balance to settle in this group.',
    ));

    await entries.create(
      EntryDraft.settlement(
        groupId: g.groupId,
        currency: 'INR',
        amountMinor: 120000,
        fromMemberId: g.priya,
        toMemberId: g.ravi,
      ),
      createdBy: g.priya,
    );
    expect(await remind('profile-priya'), isNull);
  });

  test('a reminder for a debt that is gone produces nothing', () async {
    final g = await seed();
    await addExpense(g, description: 'Dinner');

    Future<({String title, String body})?> remind({
      required String reader,
      required String from,
      String currency = 'INR',
    }) => composeEventNotification(
      entries: entries,
      groups: groups,
      profiles: profiles,
      currencies: currencies,
      activity: activity,
      myProfileId: reader,
      push: _push(g.groupId, PushKind.reminder, from, currency: currency),
    );

    // Ravi is owed, so a reminder addressed to him has nothing to say.
    expect(await remind(reader: 'profile-ravi', from: g.priya), isNull);
    expect(
      await remind(reader: 'profile-priya', from: g.ravi, currency: 'EUR'),
      isNull,
    );
  });

  test('the route opens the group, which owns refresh', () {
    expect(groupNotificationRoute('g1'), '/g/g1');
  });
}
