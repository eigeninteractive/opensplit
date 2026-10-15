import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/data/platform/app_update_service.dart';
import 'package:opensplit/data/repositories/drift_entry_repository.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/data/sync/api_client.dart';
import 'package:opensplit/domain/entry_draft.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

class _Updates extends AppUpdateService {
  int attempts = 0;
  @override
  bool get isSupported => false;
  @override
  Future<void> updateRequired() async {
    attempts++;
  }
}

void main() {
  testWidgets(
    'retirement leaves saved expense details and navigation readable',
    (tester) async {
      final db = await testDatabase();
      addTearDown(db.close);
      final access = ApiAccess();
      addTearDown(access.dispose);
      final updates = _Updates();
      final groups = DriftGroupRepository(db, accountId: testAccountId);
      final made = await groups.createGroup(
        name: 'Saved trip',
        defaultCurrency: 'INR',
        creatorDisplayName: 'Ravi',
        creatorProfileId: testAccountId,
      );
      final expense = await DriftEntryRepository(db).create(
        EntryDraft(
          groupId: made.group.id,
          currency: 'INR',
          amountMinor: 10000,
          description: 'Saved dinner',
          split: EqualSplit([made.creator.id]),
          payerAmounts: {made.creator.id: 10000},
        ),
        createdBy: made.creator.id,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        signedInApp(
          db: db,
          prefs: prefs,
          overrides: [
            apiAccessProvider.overrideWithValue(access),
            appUpdateServiceProvider.overrideWithValue(updates),
          ],
          child: const OpenSplitApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/g/${made.group.id}/e/${expense.id}');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      access.requireUpdate();
      await tester.pumpAndSettle();
      expect(find.text('Expense'), findsOneWidget);
      expect(find.textContaining('Saved data is read-only'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Delete',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('History'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('History'), findsOneWidget);
      if (!kIsWeb) {
        await tester.tap(find.text('Update OpenSplit'));
        await tester.pumpAndSettle();
        expect(updates.attempts, 1);
      }
      expect(find.textContaining('Saved data is read-only'), findsOneWidget);
      router.go('/g/${made.group.id}');
      await tester.pumpAndSettle();
      expect(find.text('Saved dinner'), findsOneWidget);
      expect(find.text('Group unavailable'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      router.go('/g/${made.group.id}/add');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Update OpenSplit to make changes.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
      router.go('/g/${made.group.id}/settings');
      await tester.pumpAndSettle();
      expect(find.text('Export this group'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
