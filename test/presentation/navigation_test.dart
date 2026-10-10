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
Future<void> _swipeBack(WidgetTester tester) async {
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
  await send('commitBackGesture');
  await tester.pumpAndSettle();
}

/// A group with nothing in it, so there is something to drill into.
Future<void> _seedGroup(AppDatabase db, {DateTime? archivedAt}) async {
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
          archivedAt: Value(archivedAt),
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    await seedReferenceData(db);
  });
  tearDown(() => db.close());

  // The rule the whole route table is built around: a screen either shows the
  // navigation bar, in which case it is a destination and there is nothing to
  // go back to, or it does not, in which case it was pushed and pops.
  group('destinations are not pushes', () {
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

  // The other half of the same rule.
  group('drilling down leaves something to come back to', () {
    testWidgets('a group covers the navigation menu and pops back', (
      tester,
    ) async {
      await _seedGroup(db);
      await _pumpApp(tester, db);

      await tester.tap(find.text('Flat 4B'));
      await tester.pumpAndSettle();

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
      expect(_router(tester).canPop(), isFalse);

      await _unmount(tester);
    });
  });

  group('back closes what is on top', () {
    testWidgets(
      'a swipe back closes the date picker, not the editor under it',
      (tester) async {
        await _seedGroup(db);
        await _pumpApp(tester, db);
        _router(tester).go('/g/g1/add');
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Change the day'));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);

        // The editor is top of its stack whichever navigator it is on, so the
        // only thing that keeps it from taking this gesture is the picker
        // being on the same stack, above it.
        await _swipeBack(tester);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byType(EntryEditorScreen), findsOneWidget);

        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        expect(find.byType(EntryEditorScreen), findsNothing);
        expect(find.byType(GroupDetailScreen), findsOneWidget);

        await _unmount(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('archived groups', () {
    testWidgets('are out of the list but not out of reach', (tester) async {
      await _seedGroup(db, archivedAt: DateTime.utc(2026, 3));
      await _pumpApp(tester, db);

      expect(
        find.text('Flat 4B'),
        findsNothing,
        reason: 'the list is for groups still in use',
      );

      await tester.tap(find.text('Archived groups (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Flat 4B'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('restoring one puts it back', (tester) async {
      await _seedGroup(db, archivedAt: DateTime.utc(2026, 3));
      await _pumpApp(tester, db);

      await tester.tap(find.text('Archived groups (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing is archived'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Flat 4B'), findsOneWidget);
      expect(find.textContaining('Archived groups'), findsNothing);

      await _unmount(tester);
    });
  });
}
