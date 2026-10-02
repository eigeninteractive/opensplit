import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/router_provider.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/domain/avatar.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:opensplit/presentation/screens/group_detail_screen.dart';
import 'package:opensplit/presentation/widgets/group_cover.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarColor, AvatarIcon;
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// How a group looks: its cover, its picture, its name, and its expenses by
/// day.
void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// A group, and two flights and a dinner in it, yesterday and today.
  Future<String> seed(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final created = await DriftGroupRepository(db).createGroup(
        name: 'Lisbon trip',
        defaultCurrency: 'EUR',
        creatorDisplayName: 'Ana',
        creatorProfileId: testAccountId,
      );
      final me = created.creator.id;
      final now = DateTime.now();
      for (final (category, days) in [
        (_flights, 1),
        (_flights, 1),
        (_restaurants, 0),
      ]) {
        final date = now.subtract(Duration(days: days));
        await DriftEntryRepository(db).create(
          EntryDraft(
            groupId: created.group.id,
            currency: 'EUR',
            amountMinor: 1000,
            description: 'Spent',
            categoryId: category,
            entryDate: date,
            split: EqualSplit([me]),
            payerAmounts: {me: 1000},
          ),
          createdBy: me,
          now: date,
        );
      }
      return created.group.id;
    }))!;
  }

  Future<void> open(WidgetTester tester, String path) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      signedInApp(db: db, prefs: prefs, child: const OpenSplitApp()),
    );
    await settle(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(OpenSplitApp)),
    ).read(routerProvider).go(path);
    await settle(tester);
  }

  Future<Group?> stored(WidgetTester tester, String id) =>
      tester.runAsync<Group?>(() => DriftGroupRepository(db).getGroup(id));

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await settle(tester);
  }

  /// Through the menu, the way a person gets there.
  Future<void> openSettings(WidgetTester tester, String id) async {
    await open(tester, '/g/$id');
    await tapAndSettle(tester, find.byTooltip('More'));
    await tapAndSettle(tester, find.text('Group settings'));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('the cover is drawn from what the group spends on', (
    tester,
  ) async {
    final id = await seed(tester);
    await open(tester, '/g/$id');

    Finder onCover(IconData icon) => find.descendant(
      of: find.byType(GroupCover),
      matching: find.byIcon(icon),
    );
    expect(onCover(Icons.flight_rounded), findsWidgets);
    expect(onCover(Icons.restaurant_rounded), findsWidgets);
    expect(
      onCover(Icons.receipt_long_rounded),
      findsNothing,
      reason: 'the stand-in is only for a group that has spent nothing',
    );
    await unmount(tester);
  });

  testWidgets('expenses are grouped under the day they happened', (
    tester,
  ) async {
    final id = await seed(tester);
    await open(tester, '/g/$id');

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // The day is the header's to say, not every row's.
    expect(find.textContaining('Ana paid'), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets('a group can be given an icon on a hue of its own', (
    tester,
  ) async {
    final id = await seed(tester);
    await openSettings(tester, id);

    await tapAndSettle(tester, find.text('Picture'));
    expect(find.text('Group picture'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tapAndSettle(tester, find.text('Icon'));
    await tapAndSettle(tester, find.byTooltip('sailing'));
    await tapAndSettle(tester, find.byTooltip('Teal'));
    await tapAndSettle(tester, save);

    expect(find.text('Group picture'), findsNothing);
    expect(
      (await stored(tester, id))?.avatar,
      const IconAvatar(AvatarIcon.sailing, color: AvatarColor.teal),
    );
    expect(find.text('An icon'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('renaming happens in a dialog, and a blank name is refused', (
    tester,
  ) async {
    final id = await seed(tester);
    await openSettings(tester, id);
    expect(find.byType(TextField), findsNothing, reason: 'a view, not a form');

    await tapAndSettle(tester, find.text('Name'));
    await tester.enterText(find.byType(TextFormField), '  ');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Rename'));
    expect(find.text('A group needs a name.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Lisbon, again');
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Rename'));

    expect((await stored(tester, id))?.name, 'Lisbon, again');
    expect(find.text('Lisbon, again'), findsOneWidget);
    await unmount(tester);
  });

  test('a day is named the way people say it', () {
    final today = DateTime.utc(2026, 10, 2);
    expect(dayLabel(today, today: today), 'Today');
    expect(dayLabel(DateTime.utc(2026, 10, 1), today: today), 'Yesterday');
    expect(dayLabel(DateTime.utc(2026, 9, 28), today: today), 'Mon, Sep 28');
    expect(
      dayLabel(DateTime.utc(2025, 12, 31), today: today),
      'Wed, Dec 31, 2025',
    );
  });
}

/// Category ids from the server's reference data.
const _flights = '8a682d2e-53f2-4d7f-9217-16e360c3eaa5';
const _restaurants = 'e7b1844c-76a3-4d2b-bd81-56a74e11f943';
