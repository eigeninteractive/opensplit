import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  await _settle(tester);
}

/// Unmounts inside the test, so Drift's query-stream cleanup timers fire while
/// there is still a tree to pump rather than tripping the binding's "timer
/// still pending" assertion during teardown.
Future<void> _unmount(WidgetTester tester) async {
  // Long enough for anything the app scheduled on a delay to have fired while
  // there is still a tree to run it in.
  await tester.pump(const Duration(seconds: 30));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _enterInto(WidgetTester tester, String label, String text) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)).first,
    text,
  );
  await tester.pump();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    await seedReferenceData(db);
  });
  tearDown(() => db.close());

  testWidgets('new group stays usable with large text and the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, db);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final scroll = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(scroll, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create group');
    expect(tester.getBottomRight(create).dy, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  group('one name, asked for once', () {
    testWidgets('an account with no name is asked, and only then', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, db);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);

      expect(
        find.text('Your name'),
        findsOneWidget,
        reason:
            'nobody has said who this is yet, so this is the one moment '
            'it is worth asking',
      );
      expect(find.text('Your name in all groups.'), findsOne);
      final nameField = find.ancestor(
        of: find.text('Group name'),
        matching: find.byType(InputDecorator),
      );
      expect(
        tester.getTopLeft(find.text('Group name')).dy,
        greaterThanOrEqualTo(tester.getTopLeft(nameField).dy),
        reason: 'the floating label stays inside the filled field',
      );

      await _enterInto(tester, 'Group name', 'Goa trip');
      await _enterInto(tester, 'Your name', 'Seenu');
      await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
      await _settle(tester);

      expect(find.text('Goa trip'), findsWidgets);

      // The second group is where this used to go wrong: the field came back
      // pre-filled from the account, and a name that differed from it was
      // written back before the group was created — so a failure there lost the
      // group while still having changed the name.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);

      expect(
        find.text('Your name'),
        findsNothing,
        reason:
            'there is one name and it is already set; a second field for '
            'it is a second place for it to disagree with itself',
      );

      await _enterInto(tester, 'Group name', 'Flat 4B');
      await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
      await _settle(tester);

      expect(find.text('Flat 4B'), findsWidgets);
      await _unmount(tester);

      // Read once the tree is gone: an awaited query while the app is still
      // mounted leaves one of Drift's stream-cleanup timers outstanding, and
      // the binding treats a pending timer as a leak.
      expect(
        (await db.select(db.profiles).getSingle()).displayName,
        'Seenu',
        reason: 'answering it names the account, which is what it is for',
      );
    });
  });
}
