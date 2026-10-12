import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/router_provider.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/avatar.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/group_detail_screen.dart';
import 'package:opensplit/presentation/widgets/group_cover.dart';
import 'package:opensplit/presentation/widgets/group_avatar_hero.dart';
import 'package:opensplit/presentation/screens/avatar_picker_screen.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarColor, AvatarIcon;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// How a group looks: its cover, its picture, its name, and its expenses by
/// day.
void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// A group, and two flights and a dinner in it, yesterday and today.
  Future<String> seed(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final created = await DriftGroupRepository(db).createGroup(
        name: 'Lisbon trip',
        defaultCurrency: 'EUR',
        creatorDisplayName: 'Ana',
        creatorProfileId: testAccountId,
      );
      final me = created.creator.id;
      final now = DateTime.now();
      for (final (category, days) in [
        (_flights, 1),
        (_flights, 1),
        (_restaurants, 0),
      ]) {
        final date = now.subtract(Duration(days: days));
        await DriftEntryRepository(db).create(
          EntryDraft(
            groupId: created.group.id,
            currency: 'EUR',
            amountMinor: 1000,
            description: 'Spent',
            categoryId: category,
            entryDate: date,
            split: EqualSplit([me]),
            payerAmounts: {me: 1000},
          ),
          createdBy: me,
          now: date,
        );
      }
      return created.group.id;
    }))!;
  }

  Future<void> open(WidgetTester tester, String path) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await settle(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(OpenSplitApp)),
    ).read(routerProvider).go(path);
    await settle(tester);
  }

  Future<Group?> stored(WidgetTester tester, String id) =>
      tester.runAsync<Group?>(() => DriftGroupRepository(db).getGroup(id));

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await settle(tester);
  }

  /// Through the menu, the way a person gets there.
  Future<void> openSettings(WidgetTester tester, String id) async {
    await open(tester, '/g/$id');
    await tapAndSettle(tester, find.byTooltip('More'));
    await tapAndSettle(tester, find.text('Group settings'));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('the cover is drawn from what the group spends on', (
    tester,
  ) async {
    final id = await seed(tester);
    await open(tester, '/g/$id');

    Finder onCover(IconData icon) => find.descendant(
      of: find.byType(GroupCover),
      matching: find.byIcon(icon),
    );
    expect(onCover(Icons.flight_rounded), findsWidgets);
    expect(onCover(Icons.restaurant_rounded), findsWidgets);
    expect(
      find.descendant(of: find.byType(GroupCover), matching: find.byType(Icon)),
      findsNWidgets(6),
      reason: 'a sparse cover keeps group identity more prominent than its art',
    );
    expect(
      onCover(Icons.receipt_long_rounded),
      findsNothing,
      reason: 'the stand-in is only for a group that has spent nothing',
    );
    await unmount(tester);
  });

  testWidgets('expenses are grouped under the day they happened', (
    tester,
  ) async {
    final id = await seed(tester);
    await open(tester, '/g/$id');

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // The day is the header's to say, not every row's.
    expect(find.textContaining('Ana paid'), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets(
    'group identity fits a narrow phone with a long name and large text',
    (tester) async {
      final id = await seed(tester);
      await tester.runAsync(() async {
        final groups = DriftGroupRepository(db);
        final group = (await groups.getGroup(id))!;
        await groups.updateGroup(
          group.copyWith(name: 'A long summer holiday with friends and family'),
        );
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, '/');
      expect(tester.takeException(), isNull);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('A long summer holiday with friends and family'),
            )
            .didExceedMaxLines,
        isFalse,
        reason: 'the group name must remain readable at large text sizes',
      );
      await tester.tap(
        find.text('A long summer holiday with friends and family'),
      );
      await settle(tester);
      expect(find.text('Expenses'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(
        find.text('A long summer holiday with friends and family'),
        findsOneWidget,
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'editing carries the expense into usable fields on the first frame',
    (tester) async {
      final id = await seed(tester);
      await open(tester, '/g/$id');
      final row = find.widgetWithText(ListTile, 'Spent').first;
      final tags = tester
          .widgetList<Hero>(
            find.descendant(of: row, matching: find.byType(Hero)),
          )
          .map((hero) => hero.tag)
          .toSet();
      expect(tags, hasLength(3));
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Edit expense'), findsOneWidget);
      for (final tag in tags) {
        final endpoints = find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == tag,
        );
        expect(
          find.descendant(of: endpoints, matching: find.byType(Text)),
          findsNothing,
          reason: 'the shared contents are flying in the overlay',
        );
      }
      await settle(tester);
      final amount = find.ancestor(
        of: find.text('Amount'),
        matching: find.byType(TextField),
      );
      await tester.enterText(amount, '12.50');
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller?.text, '12.50');
      await tester.tap(find.byType(CloseButton));
      await settle(tester);
      expect(find.text('Spent'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('the group picture opens into its editable preview and returns', (
    tester,
  ) async {
    final id = await seed(tester);
    await open(tester, '/g/$id');
    final picture = find.byType(GroupAvatarHero);
    final source = tester.getRect(picture);
    await tester.tap(find.byTooltip('Group picture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final preview = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == ('group-avatar', id),
    );
    expect(
      find.descendant(of: preview, matching: find.byType(FittedBox)),
      findsNothing,
    );
    await settle(tester);
    expect(find.byType(AvatarPickerScreen), findsOneWidget);
    expect(tester.getSize(find.byType(GroupAvatarHero)), const Size(112, 112));
    await tester.tap(find.byType(CloseButton));
    await settle(tester);
    expect(tester.getRect(picture), source);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('resizing while leaving a group keeps both routes usable', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seed(tester);
    await open(tester, '/');
    await tapAndSettle(tester, find.text('Lisbon trip'));
    final backIcon = find.descendant(
      of: find.byType(BackButton).first,
      matching: find.byType(Icon),
    );
    Focus.of(tester.element(backIcon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<IconButton>()
          ?.tooltip,
      'Settle up',
      reason: 'Tab follows the app bar in visual reading order',
    );
    await tester.tap(
      find.byType(BackButton).first,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 40));
    tester.view.physicalSize = const Size(1528, 1248);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.forward,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('OpenSplit'), findsWidgets);
    await tapAndSettle(tester, find.text('Lisbon trip'));
    final backButton = tester.element(find.byType(BackButton).first);
    tester.view.physicalSize = const Size(360, 800);
    await settle(tester);
    expect(
      tester.element(find.byType(BackButton).first),
      same(backButton),
      reason: 'resizing must preserve the mounted focusable app-bar controls',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Expenses'), findsOneWidget);
    await unmount(tester);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('a group can be given an icon on a hue of its own', (
    tester,
  ) async {
    final id = await seed(tester);
    await openSettings(tester, id);

    await tapAndSettle(tester, find.text('Picture'));
    expect(find.text('Group picture'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tapAndSettle(tester, find.text('Icon'));
    await tapAndSettle(tester, find.byTooltip('sailing'));
    await tapAndSettle(tester, find.byTooltip('Teal'));
    await tapAndSettle(tester, save);

    expect(find.text('Group picture'), findsNothing);
    expect(
      (await stored(tester, id))?.avatar,
      const IconAvatar(AvatarIcon.sailing, color: AvatarColor.teal),
    );
    expect(find.text('An icon'), findsOneWidget);
    await tapAndSettle(tester, find.text('Picture'));
    await tapAndSettle(tester, find.byTooltip('Automatic'));
    await tapAndSettle(tester, save);
    expect(
      (await stored(tester, id))?.avatar,
      const IconAvatar(AvatarIcon.sailing),
      reason: 'automatic clears the explicit hue and preserves the picture',
    );
    await unmount(tester);
  });

  testWidgets('renaming happens in a dialog, and a blank name is refused', (
    tester,
  ) async {
    final id = await seed(tester);
    await openSettings(tester, id);
    expect(find.byType(TextField), findsNothing, reason: 'a view, not a form');

    await tapAndSettle(tester, find.text('Name'));
    await tester.enterText(find.byType(TextFormField), '  ');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Rename'));
    expect(find.text('A group needs a name.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Lisbon, again');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Rename'));

    expect((await stored(tester, id))?.name, 'Lisbon, again');
    expect(find.text('Lisbon, again'), findsOneWidget);
    await unmount(tester);
  });

  test('a day is named the way people say it', () {
    final today = DateTime.utc(2026, 10, 2);
    expect(dayLabel(today, today: today), 'Today');
    expect(dayLabel(DateTime.utc(2026, 10, 1), today: today), 'Yesterday');
    expect(dayLabel(DateTime.utc(2026, 9, 28), today: today), 'Mon, Sep 28');
    expect(
      dayLabel(DateTime.utc(2025, 12, 31), today: today),
      'Wed, Dec 31, 2025',
    );
  });
}

/// Category ids from the server's reference data.
const _flights = '8a682d2e-53f2-4d7f-9217-16e360c3eaa5';
const _restaurants = 'e7b1844c-76a3-4d2b-bd81-56a74e11f943';
