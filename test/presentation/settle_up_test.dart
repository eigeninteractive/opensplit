import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind;
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
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(DropdownMenu<String>),
    ),
  );
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

  testWidgets('payment notes are protected by Back and system back', (
    tester,
  ) async {
    await _open(tester, db, '/g/g1/settle');
    final notes = find.ancestor(
      of: find.text('Payment note (optional)'),
      matching: find.byType(TextField),
    );
    await tester.enterText(notes, 'Cash after dinner');
    await _beats(tester);
    await tester.tap(find.byType(BackButton).last);
    await _beats(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _beats(tester);
    expect(
      tester.widget<TextField>(notes).controller!.text,
      'Cash after dinner',
    );
    await tester.binding.handlePopRoute();
    await _beats(tester);
    await tester.tap(find.text('Discard'));
    await _beats(tester);
    expect(find.text('Settle up'), findsNothing);
    expect(await db.select(db.entries).get(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('an untouched suggested payment leaves without a prompt', (
    tester,
  ) async {
    await _open(
      tester,
      db,
      '/g/g1/settle?from=m-ravi&to=m-priya&amount=1200&currency=INR',
    );
    await tester.tap(find.byType(BackButton).last);
    await _beats(tester);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Settle up'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('the entry URL opens a payment editor and saves a payment', (
    tester,
  ) async {
    final repository = DriftEntryRepository(db);
    final payment = (await tester.runAsync(
      () => repository.create(
        EntryDraft.settlement(
          groupId: 'g1',
          currency: 'INR',
          amountMinor: 120000,
          fromMemberId: 'm-priya',
          toMemberId: 'm-ravi',
          entryDate: DateTime.utc(2026, 8, 20),
          notes: 'Paid in cash',
        ),
        createdBy: 'm-priya',
      ),
    ))!;
    await _open(tester, db, '/g/g1/e/${payment.id}');
    expect(find.text('Edit payment'), findsOneWidget);
    expect(find.text('Priya paid Ravi'), findsOneWidget);
    expect(find.text('What was it?'), findsNothing);
    expect(find.text('Split'), findsNothing);
    expect(find.text('Pay by UPI'), findsNothing);
    expect(find.text('History'), findsOneWidget);
    expect(_shownIn(tester, 'Paid by'), 'Priya');
    expect(_shownIn(tester, 'Paid to'), 'Ravi (you)');
    Finder field(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(TextField));
    await tester.enterText(field('Amount'), '900');
    await tester.enterText(field('Payment note (optional)'), 'Bank transfer');
    await _choose(tester, 'Paid to', 'Arun');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    final saved = (await tester.runAsync(
      () => repository.getEntry(payment.id),
    ))!;
    expect(saved.row.kind, EntryKind.settlement);
    expect(saved.isSpend, isFalse);
    expect(saved.row.amountMinor, 90000);
    expect(saved.payers.single.amountMinor, 90000);
    expect(saved.shares.single.amountMinor, 90000);
    expect(saved.shares.single.memberId, 'm-arun');
    expect(saved.row.notes, 'Bank transfer');
    expect(saved.row.entryDate, payment.row.entryDate);
    expect(find.text('Priya paid Arun'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a stale payment edit keeps the draft and explains the failure', (
    tester,
  ) async {
    final repository = DriftEntryRepository(db);
    final payment = (await tester.runAsync(
      () => repository.create(
        EntryDraft.settlement(
          groupId: 'g1',
          currency: 'INR',
          amountMinor: 500,
          fromMemberId: 'm-priya',
          toMemberId: 'm-ravi',
        ),
        createdBy: 'm-priya',
      ),
    ))!;
    await _open(tester, db, '/g/g1/e/${payment.id}');
    await tester.enterText(
      find.ancestor(
        of: find.text('Payment note (optional)'),
        matching: find.byType(TextField),
      ),
      'My draft',
    );
    await tester.runAsync(
      () => repository.update(
        payment.id,
        EntryDraft.settlement(
          groupId: 'g1',
          currency: 'INR',
          amountMinor: 500,
          fromMemberId: 'm-priya',
          toMemberId: 'm-ravi',
          notes: 'Another device',
        ),
        actorId: 'm-ravi',
        expected: payment,
      ),
    );
    await _beats(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _beats(tester);
    expect(find.text('Edit payment'), findsOneWidget);
    expect(find.textContaining('changed while you were editing'), findsWidgets);
    expect(find.text('My draft'), findsOneWidget);
    final stored = (await tester.runAsync(
      () => repository.getEntry(payment.id),
    ))!;
    expect(stored.row.notes, 'Another device');
    expect(stored.row.kind, EntryKind.settlement);
    await _unmount(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'payment editing fits 320px at 200% text in ${brightness.name}',
      (tester) async {
        final payment = (await tester.runAsync(
          () => DriftEntryRepository(db).create(
            EntryDraft.settlement(
              groupId: 'g1',
              currency: 'INR',
              amountMinor: 500,
              fromMemberId: 'm-priya',
              toMemberId: 'm-ravi',
            ),
            createdBy: 'm-priya',
          ),
        ))!;
        tester.platformDispatcher
          ..textScaleFactorTestValue = 2
          ..platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _open(tester, db, '/g/g1/e/${payment.id}');
        tester.view.physicalSize = const Size(320, 640);
        await _beats(tester);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await _beats(tester);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
    );
  }

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
