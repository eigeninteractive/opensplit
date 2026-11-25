import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/entry_editor_screen.dart';
import 'package:opensplit/presentation/widgets/amount_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:opensplit_api/opensplit_api.dart' show SplitKind;

import '../harness.dart';

/// The editor seeds itself from asynchronous data, and hands its two sections
/// read-only copies of the selection which come back as new values through
/// callbacks.
Future<void> _pumpApp(
  WidgetTester tester,
  AppDatabase db, {
  Size size = const Size(400, 1600),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // A tall phone rather than the default 800x600.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
Future<void> _openEditor(WidgetTester tester) async {
  await _go(tester, '/g/g1');
  await tester.tap(find.text('Add expense'));
  await _beats(tester);
  await _unfold(tester);
}

/// Opens who paid and how it is split, which start folded to a line each.
Future<void> _unfold(WidgetTester tester) async {
  Future<void> open(String title) async {
    final tile = find.widgetWithText(ExpansionTile, title);
    await tester.ensureVisible(tile);
    await _beats(tester);
    await tester.tap(find.descendant(of: tile, matching: find.text(title)));
    await _beats(tester);
  }

  if (find.widgetWithText(TextButton, 'Several people').evaluate().isEmpty &&
      find.widgetWithText(TextButton, 'One person').evaluate().isEmpty) {
    await open('Paid by');
  }
  if (find.byType(SegmentedButton<SplitKind>).evaluate().isEmpty &&
      find.byType(DropdownMenu<SplitKind>).evaluate().isEmpty) {
    await open('Split');
  }
}

/// Opens a saved expense from its row: the read-only view, then its editor.
Future<void> _editRow(WidgetTester tester, String description) async {
  await tester.tap(find.text(description));
  await _beats(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
  await _beats(tester);
  await _unfold(tester);
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
  await tester.enterText(_field('Amount'), amount);
  await _beats(tester);
}

Finder _allocationField(String kind, String id) => find.descendant(
  of: find.byKey(ValueKey((kind, id))),
  matching: find.byType(TextField),
);

String _allocationText(WidgetTester tester, String kind, String id) =>
    tester.widget<TextField>(_allocationField(kind, id)).controller!.text;

Future<void> _chooseMethod(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownMenu<SplitKind>);
  if (dropdown.evaluate().isNotEmpty) {
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await _beats(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, label).last);
  } else {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
  }
  await _beats(tester);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedReferenceData(db);
    await seedReferenceData(db);
  });
  tearDown(() => db.close());

  for (final width in [360.0, 540.0]) {
    testWidgets('Android split changes preserve the total at width $width', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _seed(db);
      await _pumpApp(tester, db, size: Size(width, 640));
      await _go(tester, '/g/g1/add');
      await tester.runAsync(() => GoogleFonts.pendingFonts());
      await _beats(tester);
      expect(tester.testTextInput.isVisible, isFalse);

      final total = find.descendant(
        of: find.byType(AmountCard),
        matching: _field('Amount'),
      );
      await tester.enterText(total, '300');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _beats(tester);
      expect(tester.testTextInput.isVisible, isTrue);

      final split = find.widgetWithText(ExpansionTile, 'Split');
      await tester.ensureVisible(split);
      await _beats(tester);
      await tester.tap(
        find.descendant(of: split, matching: find.text('Split')),
      );
      await _beats(tester);
      final selector = find.byType(
        width == 360 ? DropdownMenu<SplitKind> : SegmentedButton<SplitKind>,
      );
      await Scrollable.ensureVisible(tester.element(selector), alignment: 0.35);
      await _beats(tester);

      await _chooseMethod(tester, 'Amounts');
      final totalInput = find.descendant(
        of: total,
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(totalInput).focusNode.hasFocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(total).controller!.text, '300');
      expect(selector.hitTestable(), findsOneWidget);

      final share = _allocationField('exact', 'm-ravi');
      await tester.enterText(share, '130');
      expect(tester.testTextInput.isVisible, isTrue);
      await _chooseMethod(tester, 'Shares');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(selector.hitTestable(), findsOneWidget);

      if (width == 360) {
        final field = find.descendant(
          of: selector,
          matching: find.byType(EditableText),
        );
        tester.widget<EditableText>(field).focusNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _beats(tester);
        expect(find.widgetWithText(MenuItemButton, 'Equally'), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _beats(tester);
      }
      await _unmount(tester);
    });
  }

  testWidgets('expense sheet expands and can open the editor at full height', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db, size: const Size(360, 640));
    await _go(tester, '/g/g1/add');
    await _type(tester, what: 'Dinner', amount: '300');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    await tester.tap(find.text('Dinner'));
    await _beats(tester);

    final sheet = find.byType(DraggableScrollableSheet);
    final bottomSheet = find.byType(BottomSheet);
    final edit = find.widgetWithText(FilledButton, 'Edit');
    final close = find.descendant(
      of: sheet,
      matching: find.byType(CloseButton),
    );
    final toolbar = find.descendant(of: sheet, matching: find.byType(AppBar));
    expect(sheet, findsOneWidget);
    expect(
      tester.widget<BottomSheet>(bottomSheet).clipBehavior,
      Clip.antiAlias,
    );
    expect(edit.hitTestable(), findsOneWidget);
    final collapsedY = tester.getTopLeft(edit).dy;
    expect(
      tester.getTopLeft(close).dy,
      greaterThan(tester.getTopLeft(bottomSheet).dy),
    );

    // Start the drag in the handle area above the toolbar.
    final handle = Offset(
      tester.getCenter(toolbar).dx,
      tester.getTopLeft(toolbar).dy - 6,
    );
    await tester.dragFrom(handle, const Offset(0, -400));
    await _beats(tester);
    expect(tester.getTopLeft(edit).dy, lessThan(collapsedY - 150));
    expect(
      tester.getTopLeft(close).dy,
      greaterThan(tester.getTopLeft(bottomSheet).dy),
    );
    expect(find.text('Paid by').hitTestable(), findsOneWidget);
    expect(find.text('Split equally').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse details'));
    await _beats(tester);
    expect(tester.getTopLeft(edit).dy, closeTo(collapsedY, 1));

    final expandIcon = find.byIcon(Icons.open_in_full);
    Focus.of(tester.element(expandIcon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _beats(tester);
    expect(tester.getTopLeft(edit).dy, lessThan(collapsedY - 150));

    await tester.tap(edit);
    await _beats(tester);
    expect(sheet, findsNothing);
    expect(find.byType(EntryEditorScreen), findsOneWidget);
    expect(find.text('Edit expense'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await _beats(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _beats(tester);
    expect(sheet, findsNothing);
    expect(find.byType(EntryEditorScreen), findsNothing);
    expect(find.text('Dinner'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('changed expense survives Close and asks before system back', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Dinner', amount: '300');
    await tester.tap(find.byType(CloseButton));
    await _beats(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _beats(tester);
    expect(tester.widget<TextField>(_field('Amount')).controller!.text, '300');
    await tester.binding.handlePopRoute();
    await _beats(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await _beats(tester);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add expense'),
      findsOneWidget,
    );
    expect(await db.select(db.entries).get(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('restoring an expense draft leaves without a discard prompt', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await tester.enterText(_field('Amount'), '300');
    await tester.enterText(_field('Amount'), '');
    await _beats(tester);
    await tester.tap(find.byType(CloseButton));
    await _beats(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add expense'),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('save errors remain visible at phone height', (tester) async {
    await _seed(db);
    await _pumpApp(tester, db, size: const Size(360, 640));
    await _openEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CloseButton));
    await _beats(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add expense'),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  for (final (size, textScale) in [
    (const Size(360, 640), 1.0),
    (const Size(360, 640), 2.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets('payer and split controls work at $size / $textScale text', (
      tester,
    ) async {
      await _seed(db);
      await _pumpApp(tester, db, size: size, textScale: textScale);
      await _openEditor(tester);
      await _type(tester, what: 'Dinner', amount: '300');
      expect(tester.takeException(), isNull);
      await Scrollable.ensureVisible(
        tester.element(find.text('Several people')),
        alignment: 0.5,
      );
      await _beats(tester);
      await tester.tap(find.text('Several people'));
      await _beats(tester);
      expect(tester.takeException(), isNull);
      for (final (label, kind) in [
        ('Amounts', SplitKind.exact),
        ('Shares', SplitKind.shares),
        ('%', SplitKind.percent),
        ('Equally', SplitKind.equal),
      ]) {
        await tester.scrollUntilVisible(
          find.text('Split'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _beats(tester);
        if (find.text('Split method').evaluate().isNotEmpty) {
          final dropdown = find.byType(DropdownMenu<SplitKind>);
          await Scrollable.ensureVisible(
            tester.element(dropdown),
            alignment: 0.5,
          );
          await _beats(tester);
          await tester.tap(dropdown);
          await _beats(tester);
          await tester.tap(find.widgetWithText(MenuItemButton, label).last);
          await _beats(tester);
          expect(
            tester.widget<DropdownMenu<SplitKind>>(dropdown).initialSelection,
            kind,
          );
        } else {
          await Scrollable.ensureVisible(
            tester.element(find.text(label)),
            alignment: 0.5,
          );
          await _beats(tester);
          await tester.tap(find.text(label));
          await _beats(tester);
          expect(
            tester
                .widget<SegmentedButton<SplitKind>>(
                  find.byType(SegmentedButton<SplitKind>),
                )
                .selected,
            {kind},
          );
        }
        await _beats(tester);
        expect(tester.takeException(), isNull);
      }
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(ExpansionTile, 'When')),
        alignment: 0.5,
      );
      await _beats(tester);
      await tester.tap(find.text('When'));
      await _beats(tester);
      final calendar = find.descendant(
        of: find.widgetWithText(ListTile, 'Date'),
        matching: find.byIcon(Icons.calendar_today_outlined),
      );
      final clearTimeIcon = find.descendant(
        of: find.byTooltip('Remove the time'),
        matching: find.byIcon(Icons.close),
      );
      expect(tester.getCenter(calendar).dx, tester.getCenter(clearTimeIcon).dx);
      await tester.ensureVisible(find.byTooltip('Remove the time'));
      await tester.tap(find.byTooltip('Remove the time'));
      await _beats(tester);
      expect(find.text('Date only'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

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

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);

    final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
    expect(saved.row.description, 'Dinner');
    expect(saved.row.amountMinor, 30000);
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

  testWidgets('a new expense happened now, here, unless the time is removed', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    final before = DateTime.now().toUtc();

    await _openEditor(tester);
    await _type(tester, what: 'Chai', amount: '30');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);

    final chai = (await DriftEntryRepository(db).getEntries('g1')).single;
    expect(chai.row.timeZone, testZone);
    expect(chai.row.occurredAt!.isBefore(before), isFalse);

    await _openEditor(tester);
    await _type(tester, what: 'Snacks', amount: '60');
    await tester.ensureVisible(find.text('When'));
    await tester.tap(find.text('When'));
    await _beats(tester);
    await tester.tap(find.byTooltip('Remove the time'));
    await _beats(tester);
    expect(find.text('Date only'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);

    final snacks = (await DriftEntryRepository(db).getEntries(
      'g1',
    )).firstWhere((entry) => entry.row.description == 'Snacks');
    expect(snacks.row.occurredAt, isNull, reason: 'only the day is known');
    expect(snacks.row.timeZone, isNull);
    await _unmount(tester);
  });

  testWidgets('the category follows the description until it is picked', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    expect(find.text('Uncategorised'), findsOneWidget);

    await tester.enterText(_field('What was it?'), 'Uber');
    await _beats(tester);
    expect(find.text('Taxi & rideshare'), findsOneWidget);

    await tester.enterText(_field('What was it?'), 'Dinner at Toit');
    await _beats(tester);
    expect(find.text('Restaurants'), findsOneWidget);

    await tester.enterText(_field('What was it?'), 'Misc');
    await _beats(tester);
    expect(
      find.text('Uncategorised'),
      findsOneWidget,
      reason: 'a guess that stops matching is taken back',
    );

    await tester.tap(find.text('Uncategorised'));
    await _beats(tester);
    await tester.tap(find.text('Groceries'));
    await _beats(tester);
    await tester.enterText(_field('What was it?'), 'Beers');
    await tester.enterText(_field('Amount'), '600');
    await _beats(tester);
    expect(
      find.text('Groceries'),
      findsOneWidget,
      reason: 'a category picked by hand is kept',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
    final groceries = await (db.select(
      db.categories,
    )..where((c) => c.name.equals('Groceries'))).getSingle();
    expect(saved.row.categoryId, groceries.id);
    await _unmount(tester);
  });

  testWidgets('an edited expense keeps the category it was saved with', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Chai', amount: '90');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);

    await _editRow(tester, 'Chai');
    expect(find.text('Restaurants'), findsOneWidget);

    await tester.enterText(_field('What was it?'), 'Chai and an Uber');
    await _beats(tester);
    expect(find.text('Restaurants'), findsOneWidget);
    await tester.enterText(_field('What was it?'), 'Uber');
    await _beats(tester);
    expect(
      find.text('Restaurants'),
      findsOneWidget,
      reason: 'the saved category counts as chosen',
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);

    expect(await DriftEntryRepository(db).getEntries('g1'), hasLength(1));

    // Back on the group, the expense is a row; opening it is the edit path.
    await _editRow(tester, 'Chai');

    // Seeding an edit needs the entry as well as the ledger and the currency
    // list, and the entry is the one that arrives last.
    expect(find.text('Edit expense'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('What was it?')).controller?.text,
      'Chai',
    );
    expect(
      tester.widget<TextField>(_field('Amount')).controller?.text,
      '90.00',
    );
    await _unmount(tester);
  });

  testWidgets('amount overrides redistribute, reset and save what is shown', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Dinner', amount: '300');
    await _chooseMethod(tester, 'Amounts');
    for (final id in ['m-ravi', 'm-priya', 'm-arun']) {
      expect(_allocationText(tester, 'exact', id), '100.00');
    }
    await tester.enterText(_allocationField('exact', 'm-ravi'), '120');
    await _beats(tester);
    expect(_allocationText(tester, 'exact', 'm-ravi'), '120');
    expect(_allocationText(tester, 'exact', 'm-priya'), '90.00');
    expect(_allocationText(tester, 'exact', 'm-arun'), '90.00');
    expect(find.text('Auto'), findsNothing);
    expect(find.text('Manual'), findsNothing);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    await tester.tap(find.byTooltip("Let Ravi's value adjust"));
    await _beats(tester);
    expect(_allocationText(tester, 'exact', 'm-ravi'), '100.00');
    await tester.enterText(_allocationField('exact', 'm-ravi'), '120');
    await tester.enterText(_allocationField('exact', 'm-priya'), '80');
    await _beats(tester);
    expect(_allocationText(tester, 'exact', 'm-arun'), '100.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
    expect(saved.row.splitKind, SplitKind.exact);
    expect(
      {for (final share in saved.shares) share.memberId: share.amountMinor},
      {'m-ravi': 12000, 'm-priya': 8000, 'm-arun': 10000},
    );
    await _editRow(tester, 'Dinner');
    expect(find.byIcon(Icons.push_pin_outlined), findsNWidgets(3));
    expect(_allocationText(tester, 'exact', 'm-ravi'), '120.00');
    await tester.enterText(_field('Amount').first, '350');
    await _beats(tester);
    expect(_allocationText(tester, 'exact', 'm-arun'), '100.00');
    expect(find.textContaining('50.00 left to assign'), findsOneWidget);
    await tester.tap(find.byTooltip("Let Arun's value adjust"));
    await _beats(tester);
    expect(_allocationText(tester, 'exact', 'm-arun'), '150.00');
    expect(find.textContaining('left to assign'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Split evenly'));
    await _beats(tester);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    expect(find.text('Split evenly'), findsNothing);
    expect(
      [
        'm-ravi',
        'm-priya',
        'm-arun',
      ].map((id) => _allocationText(tester, 'exact', id)).toList()..sort(),
      ['116.66', '116.67', '116.67'],
    );
    await _unmount(tester);
  });

  testWidgets(
    'percentage remainder updates immediately and invalid inputs do not save',
    (tester) async {
      await _seed(db);
      await _pumpApp(tester, db);
      await _openEditor(tester);
      await _type(tester, what: 'Dinner', amount: '300');
      await _chooseMethod(tester, '%');
      final initial = [
        for (final id in ['m-ravi', 'm-priya', 'm-arun'])
          _allocationText(tester, 'percent', id),
      ]..sort();
      expect(initial, ['33.333333', '33.333333', '33.333334']);
      await tester.enterText(_allocationField('percent', 'm-ravi'), '40,');
      await _beats(tester);
      expect(_allocationText(tester, 'percent', 'm-ravi'), '40,');
      expect(_allocationText(tester, 'percent', 'm-priya'), '30');
      expect(_allocationText(tester, 'percent', 'm-arun'), '30');
      await tester.enterText(_allocationField('percent', 'm-ravi'), '101');
      await _beats(tester);
      expect(find.textContaining('1% over 100%'), findsOneWidget);
      expect(_allocationText(tester, 'percent', 'm-priya'), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _beats(tester);
      expect(await DriftEntryRepository(db).getEntries('g1'), isEmpty);
      await tester.enterText(_allocationField('percent', 'm-ravi'), '40');
      await _beats(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _beats(tester);
      final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
      expect(saved.row.splitKind, SplitKind.percent);
      expect(
        {for (final share in saved.shares) share.memberId: share.amountMinor},
        {'m-ravi': 12000, 'm-priya': 9000, 'm-arun': 9000},
      );
      await _unmount(tester);
    },
  );

  testWidgets('multiple payers divide only selected, unedited payer amounts', (
    tester,
  ) async {
    await _seed(db);
    await _pumpApp(tester, db);
    await _openEditor(tester);
    await _type(tester, what: 'Dinner', amount: '300');
    await tester.tap(find.text('Several people'));
    await _beats(tester);
    expect(_allocationText(tester, 'paid', 'm-ravi'), '300.00');
    expect(_allocationField('paid', 'm-priya'), findsNothing);
    await tester.tap(_splitRow('Priya').first);
    await _beats(tester);
    expect(_allocationText(tester, 'paid', 'm-ravi'), '150.00');
    expect(_allocationText(tester, 'paid', 'm-priya'), '150.00');
    await tester.enterText(_allocationField('paid', 'm-ravi'), '120');
    await _beats(tester);
    expect(_allocationText(tester, 'paid', 'm-priya'), '180.00');
    await tester.tap(find.widgetWithText(TextButton, 'Divide evenly'));
    await _beats(tester);
    expect(_allocationText(tester, 'paid', 'm-ravi'), '150.00');
    expect(_allocationText(tester, 'paid', 'm-priya'), '150.00');
    await tester.enterText(_allocationField('paid', 'm-ravi'), '120');
    await _beats(tester);
    await tester.tap(_splitRow('Arun').first);
    await _beats(tester);
    expect(_allocationText(tester, 'paid', 'm-priya'), '90.00');
    expect(_allocationText(tester, 'paid', 'm-arun'), '90.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    final saved = (await DriftEntryRepository(db).getEntries('g1')).single;
    expect(
      {for (final payer in saved.payers) payer.memberId: payer.amountMinor},
      {'m-ravi': 12000, 'm-priya': 9000, 'm-arun': 9000},
    );
    await _unmount(tester);
  });
}
