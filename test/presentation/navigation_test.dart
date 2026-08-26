import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// `group` here is the Riverpod provider function, which collides with the
// test framework's group().
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
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
///
/// Two taps rather than one, which is the trade a drawer makes: the
/// destinations are out of the way until asked for.
Future<void> _chooseDestination(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The router in scope, for asking what the navigation stack looks like.
GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

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

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // The rule the whole route table is built around: a screen either shows the
  // navigation bar, in which case it is a destination and there is nothing to
  // go back to, or it does not, in which case it was pushed and pops.
  //
  // What this replaces: Settings used to be an icon in the app bar that pushed
  // a route which then had to suppress its own page transition so it would not
  // look like a drill-down — a screen that was pushed but was not on top of
  // anything, with a back arrow that behaved differently from every other back
  // arrow in the app.
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

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
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

      expect(find.text('Nothing is archived.'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Flat 4B'), findsOneWidget);
      expect(find.textContaining('Archived groups'), findsNothing);

      await _unmount(tester);
    });
  });
}
