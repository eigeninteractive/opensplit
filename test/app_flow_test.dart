import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Drives the real screens, with only the storage swapped for an in-memory
/// database — no network exists in this build at all, so "offline" is not
/// simulated here, it is the only mode there is.
Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  await _settle(tester);
}

/// Advances the clock in fixed steps instead of using `pumpAndSettle`.
///
/// Drift keeps a cleanup timer alive for its query streams, so the tree is
/// never "settled" by pumpAndSettle's definition and it spins until it times
/// out. Fixed pumps let animations and stream deliveries land without that.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
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

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('a flatmate group can be settled end to end, offline', (
    tester,
  ) async {
    // Phone-shaped: below the 840dp breakpoint, so this exercises the tabbed
    // layout rather than the side-by-side one.
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester, db);

    // ---- Start with nothing --------------------------------------------
    expect(find.text('No groups yet'), findsOneWidget);

    // ---- Create the group ----------------------------------------------
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    await _enterInto(tester, 'Group name', 'Flat 4B');
    await _enterInto(tester, 'Your name', 'Ravi');
    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    await _settle(tester);

    expect(find.text('Flat 4B'), findsWidgets);

    // ---- Add a flatmate who does not have the app -----------------------
    await tester.tap(find.byIcon(Icons.people_outline));
    await _settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Priya');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester);

    expect(find.text('Priya'), findsOneWidget);
    expect(
      find.text('Added by someone here — no account yet'),
      findsOneWidget,
      reason: 'a placeholder is a real member, and the copy says so',
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);

    // ---- Add an expense --------------------------------------------------
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    await _enterInto(tester, 'What was it?', 'Groceries');
    await _enterInto(tester, 'How much?', '2400');
    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await _settle(tester);

    expect(find.text('Groceries'), findsOneWidget);

    // ---- Balances appear with no network, no spinner ---------------------
    await tester.tap(find.text('Balances'));
    await _settle(tester);

    expect(find.textContaining('is owed ₹1,200.00'), findsOneWidget);
    expect(find.textContaining('owes ₹1,200.00'), findsOneWidget);
    expect(
      find.text('You pay Ravi'),
      findsNothing,
      reason: 'Ravi is owed money, so he is not the one paying',
    );
    expect(find.textContaining('Priya pays you'), findsOneWidget);

    // ---- The simplified debt is explainable ------------------------------
    await tester.tap(find.byIcon(Icons.help_outline));
    await _settle(tester);

    expect(find.text('Why this payment?'), findsOneWidget);
    expect(find.text('Built from these entries'), findsOneWidget);
    expect(
      find.text('Groceries'),
      findsWidgets,
      reason: 'the debt traces back to the expense that produced it',
    );
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // ---- Settle up -------------------------------------------------------
    await tester.tap(find.widgetWithText(FilledButton, 'Settle').first);
    await _settle(tester);

    expect(find.text('Settle up'), findsWidgets);
    expect(
      find.textContaining('OpenSplit does not move or check money'),
      findsOneWidget,
      reason: 'the app must never imply it verified a payment',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Record this payment'));
    await _settle(tester);

    // ---- A settlement is described as a payment, not as a debt -----------
    //
    // Ravi was the one owed, so being paid moves his position down — the same
    // arithmetic an expense would produce, and the reason this row used to read
    // "you owe ₹1,200.00" about money that had just arrived in his hand.
    await tester.tap(find.text('Expenses'));
    await _settle(tester);

    expect(find.textContaining('you received ₹1,200.00'), findsOneWidget);
    expect(
      find.textContaining('you owe'),
      findsNothing,
      reason: 'nobody owes anything at this point, least of all the person '
          'who was just paid',
    );

    // ---- Everyone is square ---------------------------------------------
    await tester.tap(find.text('Balances'));
    await _settle(tester);

    expect(find.text('All settled up'), findsOneWidget);
    expect(find.text('Nobody owes anybody anything.'), findsOneWidget);

    // ---- The record of all of it, with no server anywhere ---------------
    //
    // The point of the whole exercise. The authoritative record is the
    // server's — written by a trigger from the expense it commits, which is
    // what makes it something a reader can trust rather than something the
    // editing device said about itself. But it arrives only after a round
    // trip, and this screen must not be the one screen in a local-first app
    // that needs a network. So the device also records what it just did, and
    // that provisional line is what this test sees: no backend exists here at
    // all, and the feed is still complete.
    await tester.tap(find.byIcon(Icons.history));
    await _settle(tester);

    expect(find.text('Nothing yet'), findsNothing);
    expect(
      find.textContaining('added this'),
      findsNWidgets(2),
      reason: 'the groceries, and the settlement that squared them',
    );
    expect(
      find.textContaining('Ravi'),
      findsWidgets,
      reason: 'attributed to the member who did it',
    );

    // ---- Editing it says what changed ------------------------------------
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);
    await tester.tap(find.text('Expenses'));
    await _settle(tester);
    await tester.tap(find.text('Groceries'));
    await _settle(tester);

    await _enterInto(tester, 'How much?', '2000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await _settle(tester);

    await tester.tap(find.byIcon(Icons.history));
    await _settle(tester);

    expect(find.textContaining('edited this'), findsOneWidget);
    expect(
      find.textContaining('the amount, from ₹2400.00 to ₹2000.00'),
      findsOneWidget,
      reason: 'the diff is rendered in what the group actually said out loud',
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);

    // Unmount inside the test so Drift's query-stream cleanup timers fire here
    // rather than tripping the binding's "timer still pending" assertion during
    // teardown, when there is no longer a tree to pump.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
