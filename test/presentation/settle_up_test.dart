import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// Settling up hands real money to a payment app, so the handle it hands over
/// has to be the handle of the person named beside it.

Future<void> _beats(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _open(WidgetTester tester, AppDatabase db, String location) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  await _beats(tester);
  // Into the group first, then on to settling up, as a person gets there.
  final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
  router.go('/g/g1');
  await _beats(tester);
  router.push(location);
  await _beats(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.utc(2026, 8, 26);
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: 'g1',
          name: 'Flat 4B',
          defaultCurrency: 'INR',
          createdBy: const Value('m-ravi'),
          createdAt: now,
        ),
      );
  await db.batch((batch) {
    batch.insertAll(db.members, [
      MembersCompanion.insert(
        id: 'm-ravi',
        groupId: 'g1',
        profileId: const Value(testAccountId),
        displayName: 'Ravi',
        joinedAt: now,
      ),
      MembersCompanion.insert(
        id: 'm-priya',
        groupId: 'g1',
        displayName: 'Priya',
        upiVpa: const Value('priya@okaxis'),
        joinedAt: now,
      ),
      MembersCompanion.insert(
        id: 'm-arun',
        groupId: 'g1',
        displayName: 'Arun',
        upiVpa: const Value('arun@okicici'),
        joinedAt: now,
      ),
    ]);
  });
}

/// The UPI ID field, found by its label, which names the payee.
Finder _upiField(String payee) => find.ancestor(
  of: find.text("$payee's UPI ID"),
  matching: find.byType(TextField),
);

String _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

/// Opens the picker labelled [label] and picks [name] from its menu, not
/// from another picker that happens to be showing the same name.
Future<void> _choose(WidgetTester tester, String label, String name) async {
  await tester.tap(find.text(label));
  await _beats(tester);
  await tester.tap(find.widgetWithText(MenuItemButton, name).last);
  await _beats(tester);
}

Future<void> _choosePayee(WidgetTester tester, String name) =>
    _choose(tester, 'Who is being paid', name);

/// What a member picker shows, found by its label.
String _shownIn(WidgetTester tester, String label) => _textOf(
  tester,
  find.ancestor(of: find.text(label), matching: find.byType(TextField)),
);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await testDatabase();
    await _seed(db);
  });

  tearDown(() => db.close());

  testWidgets('choosing another payee hands over their UPI ID, not the last '
      "one's", (tester) async {
    await _open(tester, db, '/g/g1/settle?to=m-priya&currency=INR');
    expect(_textOf(tester, _upiField('Priya')), 'priya@okaxis');

    await _choosePayee(tester, 'Arun');
    expect(_textOf(tester, _upiField('Arun')), 'arun@okicici');

    await _unmount(tester);
  });

  testWidgets('choosing the payee as the payer clears who is being paid, on '
      'screen too', (tester) async {
    await _open(tester, db, '/g/g1/settle?to=m-priya&currency=INR');
    expect(_shownIn(tester, 'Who is being paid'), 'Priya');

    await _choose(tester, 'Who is paying', 'Priya');

    expect(_shownIn(tester, 'Who is paying'), 'Priya');
    expect(_shownIn(tester, 'Who is being paid'), isEmpty);
    // Nothing to hand a payment app until somebody is chosen.
    expect(find.text("Priya's UPI ID"), findsNothing);

    await _unmount(tester);
  });

  testWidgets('a typed UPI ID stays put until the payee changes', (
    tester,
  ) async {
    await _open(tester, db, '/g/g1/settle?to=m-priya&currency=INR');

    await tester.enterText(_upiField('Priya'), 'priya.new@okhdfc');
    await _beats(tester);
    expect(_textOf(tester, _upiField('Priya')), 'priya.new@okhdfc');

    await _choosePayee(tester, 'Arun');
    expect(_textOf(tester, _upiField('Arun')), 'arun@okicici');

    await _unmount(tester);
  });

  testWidgets('an amount typed with a decimal comma is recorded as written', (
    tester,
  ) async {
    await _open(tester, db, '/g/g1/settle?to=m-priya&currency=INR');

    await tester.enterText(
      find.ancestor(of: find.text('Amount'), matching: find.byType(TextField)),
      '12,50',
    );
    await _beats(tester);
    await tester.tap(find.text('Record this payment'));
    await _beats(tester);

    final recorded = await db.select(db.entries).getSingle();
    expect(recorded.amountMinor, 1250);

    await _unmount(tester);
  });
}
