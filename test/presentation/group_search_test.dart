import 'package:drift/drift.dart' show Value;
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

void main() {
  late AppDatabase db;
  late DriftEntryRepository entries;
  late String groupId;
  late String ana;
  late String maya;

  EntryDraft coffee({String currency = 'INR'}) => EntryDraft(
    groupId: groupId,
    currency: currency,
    amountMinor: 10000,
    description: currency == 'INR' ? 'Coffee' : 'Coffee in Tokyo',
    split: EqualSplit([ana, maya]),
    payerAmounts: {ana: 10000},
  );

  setUp(() async {
    db = await testDatabase();
    entries = DriftEntryRepository(db);
    final groups = DriftGroupRepository(db);
    final created = await groups.createGroup(
      name: 'Trip',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    groupId = created.group.id;
    ana = created.creator.id;
    maya = (await groups.addMember(groupId, displayName: 'Maya')).id;
    await entries.create(coffee(), createdBy: ana);
    await entries.create(coffee(currency: 'JPY'), createdBy: ana);
    await entries.create(
      EntryDraft.settlement(
        groupId: groupId,
        currency: 'INR',
        amountMinor: 5000,
        fromMemberId: maya,
        toMemberId: ana,
        notes: 'Coffee paid back',
      ),
      createdBy: maya,
    );
  });
  tearDown(() => db.close());

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    Size size = const Size(400, 850),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await _settle(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/g/$groupId');
    await _settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(OpenSplitApp)));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Search expenses and payments'));
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('search keeps all toolbar actions and uses independent filters', (
    tester,
  ) async {
    final scope = await mount(tester);
    expect(find.byTooltip('People'), findsOneWidget);
    expect(find.byTooltip('Settle up'), findsOneWidget);
    final filter = analyticsFilterControllerProvider(groupId);
    final held = scope.listen(filter, (_, _) {});
    scope
        .read(filter.notifier)
        .update(scope.read(filter).copyWith(currency: 'JPY', query: 'other'));
    await open(tester);
    expect(find.textContaining('across this group'), findsOneWidget);
    await tester.enterText(_search, 'cof');
    await _settle(tester);
    expect(
      find.widgetWithText(ListTile, 'Coffee').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ListTile, 'Coffee in Tokyo').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ListTile, 'Maya paid Ana').hitTestable(),
      findsOneWidget,
    );
    expect(find.textContaining('JPY 10,000'), findsOneWidget);
    expect(scope.read(filter).query, 'other');
    expect(scope.read(filter).currency, 'JPY');

    await tester.tap(find.byTooltip('Clear text'));
    await _settle(tester);
    expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    expect(find.textContaining('across this group'), findsOneWidget);
    await tester.enterText(_search, 'notfound');
    await _settle(tester);
    expect(find.text('No matching expenses or payments.'), findsOneWidget);
    await tester.enterText(_search, 'tok');
    await tester.enterText(_search, 'paid');
    await _settle(tester);
    expect(
      find.widgetWithText(ListTile, 'Coffee in Tokyo').hitTestable(),
      findsNothing,
    );
    await tester.tap(
      find.widgetWithText(ListTile, 'Maya paid Ana').hitTestable(),
    );
    await _settle(tester);
    expect(find.text('Edit payment'), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing);
    await tester.tap(find.byType(BackButton).last);
    await _settle(tester);
    await open(tester);
    expect(tester.widget<TextField>(_search).controller!.text, 'paid');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(SearchBar), findsNothing);
    held.close();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('results react while open and expenses open their editor', (
    tester,
  ) async {
    await mount(tester);
    await open(tester);
    await tester.enterText(_search, 'coffee');
    await _settle(tester);
    final added = (await tester.runAsync(
      () => entries.create(coffee(currency: 'USD'), createdBy: ana),
    ))!;
    await _settle(tester);
    expect(find.textContaining('USD 100.00'), findsOneWidget);
    await tester.runAsync(() => entries.delete(added.id, actorId: ana));
    await _settle(tester);
    expect(find.textContaining('USD 100.00'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Coffee').hitTestable());
    await _settle(tester);
    expect(find.text('Edit expense'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('losing group access dismisses its open search', (tester) async {
    await mount(tester);
    await open(tester);
    await tester.enterText(_search, 'coffee');
    await _settle(tester);
    await tester.runAsync(
      () => (db.update(db.members)..where((member) => member.id.equals(ana)))
          .write(MembersCompanion(leftAt: Value(DateTime.now()))),
    );
    await _settle(tester);
    expect(find.text('Group unavailable'), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing);
    expect(find.widgetWithText(ListTile, 'Coffee').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'narrow large text search remains usable with the keyboard',
    (tester) async {
      await mount(tester, size: const Size(320, 700));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.enterText(_search, 'coffee');
      await _settle(tester);
      expect(find.byType(SearchBar), findsOneWidget);
      await tester.tap(find.byTooltip('Clear text'));
      await _settle(tester);
      await tester.tap(find.byType(BackButton).last);
      await _settle(tester);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.byTooltip('People'), findsOneWidget);
      expect(find.byTooltip('Settle up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );
}
