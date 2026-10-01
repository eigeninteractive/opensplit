import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  /// A group of you and Maya, with each expense split evenly between you.
  ///
  /// Called through `tester.runAsync`: Drift answers on real time, which a
  /// widget test's fake clock never advances.
  Future<void> group(
    String name,
    List<({bool youPaid, String currency, int minor})> expenses,
  ) async {
    final groups = DriftGroupRepository(db);
    final entries = DriftEntryRepository(db);
    final created = await groups.createGroup(
      name: name,
      defaultCurrency: expenses.first.currency,
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    final you = created.creator.id;
    final maya = (await groups.addMember(
      created.group.id,
      displayName: 'Maya',
    )).id;
    for (final expense in expenses) {
      final payer = expense.youPaid ? you : maya;
      await entries.create(
        EntryDraft(
          groupId: created.group.id,
          currency: expense.currency,
          amountMinor: expense.minor,
          description: 'Expense',
          split: EqualSplit([you, maya]),
          payerAmounts: {payer: expense.minor},
        ),
        createdBy: payer,
      );
    }
  }

  Future<void> pumpList(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Unmounts inside the test, so Drift's query-stream cleanup timers fire
  /// while there is still a tree to pump rather than tripping the binding's
  /// "timer still pending" assertion during teardown.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Finder line(String text) => find.text(text, findRichText: true);

  testWidgets(
    'a group owing you one currency while you owe another says both',
    (tester) async {
      await tester.runAsync(
        () => group('Lisbon', [
          (youPaid: true, currency: 'GBP', minor: 10000),
          (youPaid: false, currency: 'EUR', minor: 4000),
        ]),
      );

      await pumpList(tester);

      expect(line('You are owed £50.00'), findsOneWidget);
      expect(
        line('You owe €20.00'),
        findsOneWidget,
        reason: 'the euros go the other way, and must not be listed as owed',
      );
      await unmount(tester);
    },
  );

  testWidgets('currencies that go the same way share a line', (tester) async {
    await tester.runAsync(
      () => group('Lisbon', [
        (youPaid: true, currency: 'GBP', minor: 10000),
        (youPaid: true, currency: 'EUR', minor: 4000),
      ]),
    );

    await pumpList(tester);

    expect(
      find.textContaining(
        RegExp(r'^You are owed (£50\.00 \+ €20\.00|€20\.00 \+ £50\.00)$'),
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('You owe', findRichText: true), findsNothing);
    await unmount(tester);
  });

  testWidgets('a group with nothing outstanding is settled up', (tester) async {
    await tester.runAsync(
      () => group('Even', [
        (youPaid: true, currency: 'GBP', minor: 1000),
        (youPaid: false, currency: 'GBP', minor: 1000),
      ]),
    );

    await pumpList(tester);

    expect(find.text('Settled up'), findsOneWidget);
    await unmount(tester);
  });
}
