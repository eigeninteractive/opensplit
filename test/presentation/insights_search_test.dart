import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/ledger_providers.dart';
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

Finder get _search => find.descendant(
  of: find.byType(SearchBar),
  matching: find.byType(TextField),
);

TextEditingValue _editingValue(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _search, matching: find.byType(EditableText)),
    )
    .controller
    .value;

void main() {
  late AppDatabase db;
  late String groupId;
  late String maya;

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
    maya = (await groups.addMember(groupId, displayName: 'Maya')).id;
    for (final (description, currency, amount) in [
      ('Coffee', 'INR', 10000),
      ('Dinner', 'INR', 30000),
      ('Coffee in Tokyo', 'JPY', 500),
    ]) {
      await DriftEntryRepository(db).create(
        EntryDraft(
          groupId: groupId,
          currency: currency,
          amountMinor: amount,
          description: description,
          split: EqualSplit([created.creator.id, maya]),
          payerAmounts: {created.creator.id: amount},
        ),
        createdBy: created.creator.id,
      );
    }
  });
  tearDown(() => db.close());

  Future<ProviderContainer> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await _settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(OpenSplitApp)));
  }

  Future<void> open(WidgetTester tester) async {
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/g/$groupId/insights');
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('Clear search clears text and results, retaining other filters', (
    tester,
  ) async {
    final scope = await mount(tester);
    await open(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Maya'));
    await tester.enterText(_search, 'cof');
    await _settle(tester);
    expect(find.text('1 expense'), findsOneWidget);
    expect(find.text('1 matching entry'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await _settle(tester);
    expect(_editingValue(tester).text, isEmpty);
    final filter = scope.read(analyticsFilterControllerProvider(groupId));
    expect(filter.query, isEmpty);
    expect(filter.memberId, maya);
    expect(filter.currency, 'INR');
    expect(find.text('2 expenses'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);

    await tester.enterText(_search, 'din');
    await _settle(tester);
    expect(find.text('1 expense'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Dinner'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Clear filters clears the search text as well as its query', (
    tester,
  ) async {
    final scope = await mount(tester);
    await open(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Maya'));
    await tester.enterText(_search, 'cof');
    await _settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Clear filters'));
    await _settle(tester);
    expect(_editingValue(tester).text, isEmpty);
    final filter = scope.read(analyticsFilterControllerProvider(groupId));
    expect(filter.query, isEmpty);
    expect(filter.memberId, isNull);
    expect(find.text('2 expenses'), findsOneWidget);
    expect(find.textContaining('matching entr'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('restored queries synchronize without disturbing typing', (
    tester,
  ) async {
    final scope = await mount(tester);
    final provider = analyticsFilterControllerProvider(groupId);
    final subscription = scope.listen(provider, (_, _) {});
    final controller = scope.read(provider.notifier);
    controller.update(scope.read(provider).copyWith(query: 'cof'));
    await open(tester);
    expect(_editingValue(tester).text, 'cof');
    expect(find.text('1 expense'), findsOneWidget);

    await tester.showKeyboard(_search);
    const typed = TextEditingValue(
      text: 'coffee',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 6),
    );
    tester.testTextInput.updateEditingValue(typed);
    await _settle(tester);
    expect(_editingValue(tester), typed);
    controller.update(scope.read(provider).copyWith(memberId: maya));
    await _settle(tester);
    expect(_editingValue(tester), typed);

    controller.update(scope.read(provider).copyWith(query: 'din'));
    await _settle(tester);
    expect(_editingValue(tester).text, 'din');
    expect(find.widgetWithText(ListTile, 'Dinner'), findsOneWidget);
    subscription.close();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
