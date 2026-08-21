import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `group` here is the Riverpod provider function, which collides with the
// test framework's group().
import 'package:opensplit/application/providers.dart' hide group;
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/widgets/page_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const OpenSplitApp(),
    ),
  );
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

  group('navigation rail', () {
    testWidgets('is absent on a phone, where the app bar is the navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      expect(find.byType(NavigationRail), findsNothing);
      await _unmount(tester);
    });

    testWidgets('appears on a desktop browser, which has no other chrome', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('navigates to settings and marks it selected', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpApp(tester, db);
      await tester.tap(find.byIcon(Icons.settings_outlined).last);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.text('Your name'), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1,
      );
      await _unmount(tester);
    });
  });
}
