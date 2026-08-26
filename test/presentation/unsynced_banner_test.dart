import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/sync/outbox_queue.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/widgets/unsynced_changes_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The banner is the only thing that tells anyone a write never reached the
/// server. Everything upstream of it — the dead letter, the recorded reason —
/// already existed and told nobody, which is exactly the failure these tests
/// exist to keep fixed.
Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(home: Scaffold(body: UnsyncedChangesBanner())),
    ),
  );
  await _beats(tester);
}

Future<void> _beats(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Tears the tree down while the binding is still pumping.
///
/// Cancelling a Drift query stream schedules a zero-duration cleanup timer. If
/// the tree is disposed by the test framework instead, that timer is still
/// pending when it checks, and every test in the file fails on an invariant
/// that has nothing to do with what it was testing.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _deadLetter(
  AppDatabase db, {
  required String entryId,
  required String description,
  required String error,
}) async {
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: 'g1',
          name: 'Goa trip',
          defaultCurrency: 'INR',
          createdBy: const Value('me'),
          createdAt: DateTime.utc(2026, 8, 21),
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await db
      .into(db.entries)
      .insert(
        EntriesCompanion.insert(
          id: entryId,
          groupId: 'g1',
          kind: EntryKind.expense,
          currency: 'INR',
          amountMinor: 100000,
          entryDate: DateTime.utc(2026, 8, 21),
          splitKind: SplitKind.equal,
          createdBy: 'me',
          createdAt: DateTime.utc(2026, 8, 21),
          updatedAt: DateTime.utc(2026, 8, 21),
          description: Value(description),
        ),
      );
  await db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          id: OutboxQueue.idFor(OutboxTarget.entry, entryId),
          operation: OutboxTarget.entry.name,
          targetId: entryId,
          createdAt: DateTime.utc(2026, 8, 21),
          lastError: Value(error),
          deadLetteredAt: Value(DateTime.utc(2026, 8, 21)),
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('nothing is shown when every write has landed', (tester) async {
    await _pump(tester, db);
    expect(find.byType(Card), findsNothing);
    await _teardown(tester);
  });

  testWidgets('a refused write is named and its consequence stated', (
    tester,
  ) async {
    await _deadLetter(
      db,
      entryId: 'e1',
      description: "Dinner at Britto's",
      error: 'entry does not balance',
    );
    await _pump(tester, db);

    expect(find.text('One change could not be saved'), findsOneWidget);

    // Naming the expense matters more than the count: "a change" is not
    // something anyone can act on, and the whole point is that the user can
    // tell which of their expenses the rest of the group cannot see.
    expect(find.textContaining("Dinner at Britto's"), findsOneWidget);
    expect(find.textContaining('this device only'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('the server\'s own words are available, unedited', (
    tester,
  ) async {
    await _deadLetter(
      db,
      entryId: 'e1',
      description: 'Taxi',
      error: 'new row violates row-level security policy for table "entries"',
    );
    await _pump(tester, db);

    await tester.tap(find.text('Details'));
    await _beats(tester);

    expect(
      find.textContaining('row-level security'),
      findsOneWidget,
      reason: 'the one person who opens this is debugging a wrong balance',
    );
    await _teardown(tester);
  });

  testWidgets('several refusals are counted, not just the first', (
    tester,
  ) async {
    await _deadLetter(
      db,
      entryId: 'e1',
      description: 'Taxi',
      error: 'entry does not balance',
    );
    await _deadLetter(
      db,
      entryId: 'e2',
      description: 'Groceries',
      error: 'entry does not balance',
    );
    await _pump(tester, db);

    expect(find.text('2 changes could not be saved'), findsOneWidget);
    await _teardown(tester);
  });
}
