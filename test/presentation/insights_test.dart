import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;
  late String groupId;

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
    final ana = created.creator.id;
    final maya = (await groups.addMember(groupId, displayName: 'Maya')).id;
    for (final (description, currency, amount, payer, split) in [
      ('Coffee', 'INR', 10000, ana, [ana, maya]),
      ('Dinner', 'INR', 30000, maya, [ana, maya]),
      ('Museum', 'INR', 20000, maya, [maya]),
      ('Coffee in Tokyo', 'JPY', 500, ana, [ana, maya]),
    ]) {
      await DriftEntryRepository(db).create(
        EntryDraft(
          groupId: groupId,
          currency: currency,
          amountMinor: amount,
          description: description,
          split: EqualSplit(split),
          payerAmounts: {payer: amount},
        ),
        createdBy: ana,
      );
    }
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await _settle(tester);
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/g/$groupId/insights');
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('leads with what the group spent in its most used currency', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('The group spent'), findsOneWidget);
    expect(find.text('₹600.00'), findsWidgets);
    expect(find.textContaining(RegExp(r'^3 expenses')), findsOneWidget);
    expect(find.text('Who paid and who spent'), findsOneWidget);
    expect(find.text('Biggest expenses'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'JPY'));
    await _settle(tester);
    expect(find.textContaining(RegExp(r'^1 expense')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('You counts your own shares and what you paid', (tester) async {
    await open(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<bool>),
        matching: find.text('You'),
      ),
    );
    await _settle(tester);

    expect(find.text('Your share'), findsOneWidget);
    expect(find.text('₹200.00'), findsWidgets);
    expect(find.text('You paid ₹100.00 of the bills.'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^2 expenses')), findsOneWidget);
    expect(find.text('Who paid and who spent'), findsNothing);
    expect(find.text('Museum'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a person opens the expenses behind their figures', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Maya').first);
    await _settle(tester);

    expect(find.text('₹600.00 · 3 expenses'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Museum').last);
    await _settle(tester);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('You were not part of this.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a period with nothing in it says so', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'All time'));
    await _settle(tester);
    await tester.tap(find.text('Last month'));
    await _settle(tester);

    expect(find.text('No matching expenses'), findsOneWidget);
    expect(find.text('Where it went'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
