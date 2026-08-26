import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// The editor seeds itself from asynchronous data, and hands its two sections
/// read-only copies of the selection which come back as new values through
/// callbacks. Both used to work the other way round — seeded inside `build`,
/// with the sections editing the screen's own collections in place — so these
/// hold the corrected shape down.
///
/// Driven through the real router rather than pumped on its own: saving calls
/// [goBack], which needs one, and the editor is only ever reached by a push.
Future<void> _pumpApp(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // A tall phone rather than the default 800x600. The editor is a long form and
  // its save button sits below three members' worth of split rows, so on the
  // default surface the thing under test is off screen. Kept under the 840dp
  // rail breakpoint so the layout is still the phone one.
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
  );
  await _beats(tester);
}

Future<void> _go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await _beats(tester);
}

/// Opens the editor the way a person does: into the group, then the button.
///
/// Deliberately not `go('/g/g1/add')`. Going straight to a two-level location
/// builds both pages in one frame, and SelectionArea — which wraps the whole
/// app — walks the selectables of a page whose transition has not been laid out
/// yet, tripping a framework assertion that has nothing to do with this screen.
Future<void> _openEditor(WidgetTester tester) async {
  await _go(tester, '/g/g1');
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Add expense'));
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

/// The field carrying [label], found by its label rather than by position: the
/// currency and category pickers are DropdownMenus, which are TextFields too.
Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

/// The split section's row for [name], as opposed to the payer chip.
Finder _splitRow(String name) => find.descendant(
  of: find.byType(CheckboxListTile),
  matching: find.text(name),
);

/// Three people in a group, so a split has something to divide.
Future<void> _seed(AppDatabase db) async {
  final now = DateTime.utc(2026, 8, 26);
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: 'g1',
          name: 'Flat 4B',
          defaultCurrency: 'INR',
          createdBy: const Value(testAccountId),
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
        joinedAt: now,
      ),
      MembersCompanion.insert(
        id: 'm-arun',
        groupId: 'g1',
        displayName: 'Arun',
        joinedAt: now,
      ),
    ]);
  });
}

Future<void> _type(
  WidgetTester tester, {
  required String what,
  required String amount,
}) async {
  await tester.enterText(_field('What was it?'), what);
  await tester.enterText(_field('How much?'), amount);
  await _beats(tester);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('a new expense starts with everyone in the split', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);

    // Also the assertion that seeding ran at all: none of it happens during
    // build any more, so if the listener were wired wrongly the form would be
    // empty rather than merely stale.
    final rows = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(rows, hasLength(3), reason: 'every member is offered');
    expect(
      rows.every((row) => row.value ?? false),
      isTrue,
      reason: 'and everybody splits by default',
    );
    await _unmount(tester);
  });

  testWidgets('taking somebody out of the split changes what is saved', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Dinner', amount: '300');

    // Exercises the callback path rather than an in-place edit of the screen's
    // own set, which is what this used to be.
    await tester.tap(_splitRow('Arun'));
    await _beats(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await _beats(tester);

    final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
    expect(saved.description, 'Dinner');
    expect(saved.amountMinor, 30000);
    expect(
      {for (final share in saved.shares) share.memberId},
      {'m-ravi', 'm-priya'},
      reason: 'Arun was taken out before saving',
    );
    expect(
      [for (final share in saved.shares) share.amountMinor],
      everyElement(15000),
      reason: 'and the remaining two split it evenly',
    );
    expect(
      {for (final payer in saved.payers) payer.memberId},
      {'m-ravi'},
      reason: 'the person adding it paid, by default',
    );
    await _unmount(tester);
  });

  testWidgets('editing an existing expense fills the form from it', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Chai', amount: '90');
    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await _beats(tester);

    expect(await DriftEntryRepository(db).getEntries('g1'), hasLength(1));

    // Back on the group, the expense is a row; opening it is the edit path.
    await tester.tap(find.text('Chai'));
    await _beats(tester);

    // Seeding an edit needs the entry as well as the ledger and the currency
    // list, and the entry is the one that arrives last.
    expect(find.text('Edit expense'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('What was it?')).controller?.text,
      'Chai',
    );
    expect(
      tester.widget<TextField>(_field('How much?')).controller?.text,
      '90.00',
    );
    await _unmount(tester);
  });
}
