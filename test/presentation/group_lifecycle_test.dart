import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

void main() {
  testWidgets('a changed balance while confirming departure is explained', (
    tester,
  ) async {
    final db = await testDatabase();
    addTearDown(db.close);
    final groups = DriftGroupRepository(db, accountId: testAccountId);
    final entries = DriftEntryRepository(db, accountId: testAccountId);
    final made = await groups.createGroup(
      name: 'Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ravi',
      creatorProfileId: testAccountId,
    );
    final other = await groups.addMember(made.group.id, displayName: 'Priya');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/g/${made.group.id}/settings');
    await tester.pumpAndSettle();
    expect(find.textContaining('Archive'), findsNothing);
    await tester.ensureVisible(find.text('Leave group'));
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this group?'), findsOneWidget);
    await entries.create(
      EntryDraft(
        groupId: made.group.id,
        currency: 'INR',
        amountMinor: 100,
        description: 'Arrived during confirmation',
        split: EqualSplit([made.creator.id, other.id]),
        payerAmounts: {made.creator.id: 100},
      ),
      createdBy: made.creator.id,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Settle this member'), findsOneWidget);
    expect(
      (await groups.getMembers(
        made.group.id,
      )).any((member) => member.id == made.creator.id),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'confirmed leave returns to the list when its screen loses access',
    (tester) async {
      final db = await testDatabase();
      addTearDown(db.close);
      final groups = DriftGroupRepository(db, accountId: testAccountId);
      final made = await groups.createGroup(
        name: 'Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: testAccountId,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/g/${made.group.id}/settings');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Leave group'));
      await tester.tap(find.text('Leave group'));
      await tester.pumpAndSettle();
      expect(find.textContaining('permanently deletes'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Trip'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'departed accounts cannot see cached group data through any route',
    (tester) async {
      final db = await testDatabase();
      addTearDown(db.close);
      final groups = DriftGroupRepository(db, accountId: testAccountId);
      final entries = DriftEntryRepository(db, accountId: testAccountId);
      final made = await groups.createGroup(
        name: 'Private trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: testAccountId,
      );
      final entry = await entries.create(
        EntryDraft(
          groupId: made.group.id,
          currency: 'INR',
          amountMinor: 100,
          description: 'Private expense',
          split: EqualSplit([made.creator.id]),
          payerAmounts: {made.creator.id: 100},
        ),
        createdBy: made.creator.id,
      );
      await groups.leaveGroup(memberId: made.creator.id);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      for (final suffix in [
        '',
        '/settings',
        '/members',
        '/add',
        '/settle',
        '/picture',
        '/activity',
        '/insights',
        '/e/${entry.id}',
      ]) {
        router.go('/g/${made.group.id}$suffix');
        await tester.pumpAndSettle();
        expect(find.text('Group unavailable'), findsOneWidget);
        expect(find.text('Private trip'), findsNothing);
        expect(find.text('Private expense'), findsNothing);
        expect(find.text('Save'), findsNothing);
        expect(find.text('Export this group'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'removing somebody who is not settled names the action and the way out',
    (tester) async {
      final db = await testDatabase();
      addTearDown(db.close);
      final groups = DriftGroupRepository(db, accountId: testAccountId);
      final entries = DriftEntryRepository(db, accountId: testAccountId);
      final made = await groups.createGroup(
        name: 'Trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: testAccountId,
      );
      final priya = await groups.addMember(made.group.id, displayName: 'Priya');
      await entries.create(
        EntryDraft(
          groupId: made.group.id,
          currency: 'INR',
          amountMinor: 20000,
          description: 'Dinner',
          split: EqualSplit([made.creator.id, priya.id]),
          payerAmounts: {made.creator.id: 20000},
        ),
        createdBy: made.creator.id,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/g/${made.group.id}/members');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      expect(find.textContaining('not settled'), findsNothing);
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();

      expect(find.text("Can't remove Priya yet"), findsOneWidget);
      expect(find.textContaining('owes ₹100.00'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Settle up'), findsOneWidget);
      expect(
        (await groups.getMembers(made.group.id)).any((m) => m.id == priya.id),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
