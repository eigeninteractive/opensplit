import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// `group` here is the Riverpod provider function, which collides with the
// test framework's group().
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/widgets/page_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  await _beats(tester);
}

Future<void> _beats(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('PageBody', () {
    testWidgets('caps content width on a wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PageBody(child: SizedBox.expand(key: Key('content'))),
          ),
        ),
      );

      final width = tester.getSize(find.byKey(const Key('content'))).width;
      expect(width, 760);
    });

    testWidgets('takes the full width on a phone', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PageBody(child: SizedBox.expand(key: Key('content'))),
          ),
        ),
      );

      // Nothing about the phone layout changes: below the cap this is exactly
      // the width the page would have had anyway.
      expect(tester.getSize(find.byKey(const Key('content'))).width, 400);
    });
  });

  // One set of destinations, two presentations of it. Which one is on screen
  // is the only thing the width decides — there is never both, and never
  // neither.
  group('the navigation surface', () {
    testWidgets('stays usable on a small screen at 200% text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpApp(tester, db);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('desktop navigation enters the keyboard focus order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(
        FocusManager.instance.primaryFocus!.context,
        isNotNull,
        reason: 'a browser user must be able to enter the app with Tab',
      );
      await _unmount(tester);
    });

    testWidgets('is a drawer behind a menu button on a phone', (tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      expect(find.byType(NavigationRail), findsNothing);

      // Closed to begin with: a drawer costs a tap, which is the trade it
      // makes for giving the page its full height back.
      expect(find.byType(NavigationDrawer), findsNothing);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await _beats(tester);

      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('is a rail on a desktop browser, which has no other chrome', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      expect(find.byType(NavigationRail), findsOneWidget);
      // No menu button beside it: the rail is already showing everything a
      // drawer would have to be opened to see.
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('the drawer switches destination and closes behind it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await _beats(tester);

      await tester.tap(find.text('Account'));
      await _beats(tester);

      expect(find.text('Your name'), findsOneWidget);
      expect(
        find.byType(NavigationDrawer),
        findsNothing,
        reason: 'it closes rather than sitting open over the new screen',
      );
      await _unmount(tester);
    });

    testWidgets('navigates to a destination and marks it selected', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);

      // Account is the middle destination, and holds the one name a person has
      // — it used to be a field three quarters of the way down Settings.
      await tester.tap(find.byIcon(Icons.person_outline).last);
      await _beats(tester);

      expect(find.text('Your name'), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );

      await tester.tap(find.byIcon(Icons.settings_outlined).last);
      await _beats(tester);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        2,
      );
      await _unmount(tester);
    });
  });
}
