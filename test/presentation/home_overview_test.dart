import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  /// A group where Ana paid [amount] for herself and one other person.
  Future<void> group(String name, int amount) async {
    final groups = DriftGroupRepository(db);
    final created = await groups.createGroup(
      name: name,
      defaultCurrency: 'INR',
      creatorDisplayName: 'Ana',
      creatorProfileId: testAccountId,
    );
    final ana = created.creator.id;
    final other = await groups.addMember(created.group.id, displayName: 'Bo');
    await DriftEntryRepository(db).create(
      EntryDraft(
        groupId: created.group.id,
        currency: 'INR',
        amountMinor: amount,
        description: 'Dinner',
        split: EqualSplit([ana, other.id]),
        payerAmounts: {ana: amount},
      ),
      createdBy: ana,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await _settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('adds up what you are owed across groups', (tester) async {
    await group('Flat', 20000);
    await group('Trip', 30000);
    await mount(tester);

    expect(find.text('Across 2 groups'), findsOneWidget);
    expect(find.bySemanticsLabel('You are owed ₹250.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('says nothing overall when one group is the whole story', (
    tester,
  ) async {
    await group('Flat', 20000);
    await mount(tester);

    expect(find.textContaining('Across'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  test(
    'a group is unseen until it is first opened, then seen from then',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final seen = groupSeenAtProvider('g1');

      expect(container.read(seen), isNull);
      await container.read(seen.notifier).markNow();

      expect(container.read(seen), isNotNull);
      expect(prefs.getInt('group_seen_at.g1'), isNotNull);
      expect(container.read(groupSeenAtProvider('g2')), isNull);
    },
  );
}
