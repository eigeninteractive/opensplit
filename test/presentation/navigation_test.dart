import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// `group` here is the Riverpod provider function, which collides with the
// test framework's group().
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/entry_editor_screen.dart';
import 'package:opensplit/presentation/screens/group_detail_screen.dart';
import 'package:opensplit/presentation/screens/group_list_screen.dart';
import 'package:opensplit/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

/// Opens the drawer and picks a destination by name.
Future<void> _chooseDestination(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The router in scope, for asking what the navigation stack looks like.
GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

/// Swipes back from the screen's edge, as Android's predictive back does.
///
/// Unlike a back button press, a gesture is claimed by the page that is top of
/// its own navigator, which is what lets a page under a dialog take it.
Future<void> _swipeBack(
  WidgetTester tester, {
  bool cancel = false,
  Finder? preview,
}) async {
  Future<void> send(String method, [Object? arguments]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
  await send('startBackGesture', {
    'touchOffset': [5.0, 300.0],
    'progress': 0.0,
    'swipeEdge': 0,
  });
  await tester.pump();
  await send('updateBackGestureProgress', {
    'touchOffset': [155.0, 300.0],
    'progress': 0.4,
    'swipeEdge': 0,
  });
  await tester.pump();
  if (preview != null) expect(preview, findsOneWidget);
  await send(cancel ? 'cancelBackGesture' : 'commitBackGesture');
  await tester.pumpAndSettle();
}

/// A group with nothing in it, so there is something to drill into.
Future<void> _seedGroup(AppDatabase db, {bool left = false}) async {
  // Currencies are reference data the database ships with, so there is
  // nothing to seed there — only the group.
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: 'g1',
          name: 'Flat 4B',
          defaultCurrency: 'INR',
          createdBy: const Value(testAccountId),
          createdAt: DateTime.utc(2026),
        ),
      );
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: testAccountId,
          groupId: 'g1',
          profileId: const Value(testAccountId),
          displayName: 'Ravi',
          joinedAt: DateTime.utc(2026),
          leftAt: Value(left ? DateTime.utc(2026, 3) : null),
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
  });
  tearDown(() => db.close());

  // The rule the whole route table is built around: a screen either shows the
  // navigation bar, in which case it is a destination and there is nothing to
  // go back to, or it does not, in which case it was pushed and pops.
  group('destinations are not pushes', () {
    testWidgets('the rail labels extend on wide desktops', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1000, 800);
      await _pumpApp(tester, db);

      final rail = find.byType(NavigationRail);
      expect(tester.widget<NavigationRail>(rail).extended, isFalse);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationRail>(rail).extended, isTrue);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Account saved'), findsNothing);
      expect(
        find.descendant(of: rail, matching: find.text('Account')),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets(
      'the phone layout has one menu, not a settings button beside it',
      (tester) async {
        await _pumpApp(tester, db);

        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.settings_outlined),
          ),
          findsNothing,
          reason: 'navigation belongs in one place, and this is not it',
        );

        await _unmount(tester);
      },
    );

    testWidgets('switching destination leaves nothing to pop', (tester) async {
      await _pumpApp(tester, db);

      expect(_router(tester).canPop(), isFalse, reason: 'starts at the root');

      await _chooseDestination(tester, 'Settings');

      // At least one, not exactly one: Settings is under a Material 3 large top
      // app bar, and SliverAppBar.large puts its headline in both the collapsed
      // title slot and the expanded FlexibleSpaceBar, so the word legitimately
      // appears twice while the bar is open.
      expect(find.widgetWithText(AppBar, 'Settings'), findsAtLeastNWidgets(1));
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(
        find.byType(BackButton),
        findsNothing,
        reason: 'Settings is beside Groups, not on top of it',
      );
      expect(_router(tester).canPop(), isFalse);

      await _unmount(tester);
    });

    testWidgets('and comes back to a Groups list that kept its place', (
      tester,
    ) async {
      await _seedGroup(db);
      await _pumpApp(tester, db);

      await _chooseDestination(tester, 'Settings');
      await _chooseDestination(tester, 'Groups');

      expect(find.text('Flat 4B'), findsOneWidget);

      await _unmount(tester);
    });
  });

  testWidgets('switches destinations immediately with reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester, db);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.byType(GroupListScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _unmount(tester);
  });

  // The other half of the same rule.
  group('drilling down leaves something to come back to', () {
    testWidgets('a group covers the navigation menu and pops back', (
      tester,
    ) async {
      await _seedGroup(db);
      await _pumpApp(tester, db);

      await tester.tap(find.text('Flat 4B'));
      await tester.pumpAndSettle();

      final detail = tester.element(find.byType(GroupDetailScreen));
      expect(GoRouterState.of(detail).uri.path, '/g/g1');
      expect(
        find.byTooltip('Open navigation menu'),
        findsNothing,
        reason: 'a group is a screen you are inside, not a destination',
      );
      expect(
        _router(tester).canPop(),
        isTrue,
        reason: 'a pushed screen has to be poppable, or back is a dead end',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(find.text('Flat 4B'), findsOneWidget);
      expect(_router(tester).canPop(), isFalse);

      await _unmount(tester);
    });
  });

  group('back closes what is on top', () {
    testWidgets('predictive Back closes the top screen and can be cancelled', (
      tester,
    ) async {
      await _seedGroup(db);
      await _pumpApp(tester, db);
      await tester.tap(find.text('Flat 4B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('When'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // The editor is top of its stack whichever navigator it is on, so the
      // only thing that keeps it from taking this gesture is the picker
      // being on the same stack, above it.
      await _swipeBack(tester);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(EntryEditorScreen), findsOneWidget);

      // The group is drawn back in under the gesture, and nothing on the
      // way trips an assertion.
      await _swipeBack(tester);
      expect(find.byType(EntryEditorScreen), findsNothing);
      expect(find.byType(GroupDetailScreen), findsOneWidget);

      await _swipeBack(
        tester,
        cancel: true,
        preview: find.byType(GroupListScreen),
      );
      expect(find.byType(GroupDetailScreen), findsOneWidget);
      await _swipeBack(tester);
      expect(find.byType(GroupListScreen), findsOneWidget);
      expect(find.text('Flat 4B'), findsOneWidget);

      await _unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  testWidgets('departed groups disappear and direct links reveal no history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _seedGroup(db, left: true);
    await _pumpApp(tester, db);
    expect(find.text('Flat 4B'), findsNothing);
    expect(find.textContaining('Past groups'), findsNothing);
    _router(tester).go('/g/g1');
    await tester.pumpAndSettle();
    expect(find.text('Group unavailable'), findsOneWidget);
    expect(find.text('Flat 4B'), findsNothing);
    expect(find.text('Add expense'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
