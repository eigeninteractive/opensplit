import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/group_signals.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// A server that answers every reminder the same way.
class _FakeSignals implements GroupSignals {
  _FakeSignals(this.outcome);

  final api.ReminderOutcome outcome;
  final reminded = <(String memberId, String currency)>[];

  @override
  Future<api.Reminder> remind({
    required String groupId,
    required String memberId,
    required String currency,
  }) async {
    reminded.add((memberId, currency));
    return api.Reminder(outcome: outcome, sentAt: null);
  }

  @override
  Future<DateTime> markSeen(String groupId, DateTime seenAt) async => seenAt;
}

void main() {
  late AppDatabase db;
  late String groupId;
  late String ana;
  late String bo;
  late String cy;

  setUp(() async {
    db = await testDatabase();
    final groups = DriftGroupRepository(db);
    final created = await groups.createGroup(
      name: 'Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    groupId = created.group.id;
    ana = created.creator.id;
    // Bo has an account and so a device to notify. Cy is only a name.
    bo = (await groups.addMember(
      groupId,
      displayName: 'Bo',
      profileId: 'profile-bo',
    )).id;
    cy = (await groups.addMember(groupId, displayName: 'Cy')).id;
  });
  tearDown(() => db.close());

  Future<void> expense(String payer, int amount) =>
      DriftEntryRepository(db).create(
        EntryDraft(
          groupId: groupId,
          currency: 'INR',
          amountMinor: amount,
          description: 'Dinner',
          split: EqualSplit([ana, bo, cy]),
          payerAmounts: {payer: amount},
        ),
        createdBy: payer,
      );

  Future<void> openBalances(
    WidgetTester tester, {
    GroupSignals? signals,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(
        db: db,
        prefs: prefs,
        overrides: [groupSignalsProvider.overrideWithValue(signals)],
        child: const OpenSplitApp(),
      ),
    );
    await _settle(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/g/$groupId');
    await _settle(tester);
    await tester.tap(find.text('Balances'));
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('someone who owes you can be reminded, shared with or settled', (
    tester,
  ) async {
    await expense(ana, 30000);
    final signals = _FakeSignals(api.ReminderOutcome.sent);
    await openBalances(tester, signals: signals);

    expect(find.widgetWithText(FilledButton, 'Settle'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'Share'), findsNWidgets(2));
    // Only Bo has an account for a notification to reach.
    expect(find.widgetWithText(TextButton, 'Remind'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pay'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Remind'));
    await _settle(tester);

    expect(signals.reminded, [(bo, 'INR')]);
    expect(find.text('Reminder sent to Bo.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a reminder already sent today points to Share', (tester) async {
    await expense(ana, 30000);
    await openBalances(
      tester,
      signals: _FakeSignals(api.ReminderOutcome.alreadyReminded),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Remind'));
    await _settle(tester);

    expect(find.textContaining('You already reminded Bo today'), findsOne);
    await unmount(tester);
  });

  testWidgets('what you owe offers only Pay', (tester) async {
    await expense(bo, 30000);
    await openBalances(tester, signals: _FakeSignals(api.ReminderOutcome.sent));

    expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Settle'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Remind'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Share'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('with no server there is nothing to remind through', (
    tester,
  ) async {
    await expense(ana, 30000);
    await openBalances(tester);

    expect(find.widgetWithText(TextButton, 'Remind'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Share'), findsNWidgets(2));
    await unmount(tester);
  });
}
