import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/local_providers.dart';
import 'package:opensplit/application/session_providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:opensplit/data/repositories/drift_group_repository.dart';
import 'package:opensplit/presentation/widgets/link_account_prompt.dart';
import 'package:opensplit_api/opensplit_api.dart' show Account;

import '../harness.dart';

/// What a guest is told about the one thing that can end their account.

Account _account({required bool guest}) => Account(
  id: testAccountId,
  isAnonymous: guest,
  email: guest ? null : 'a@b.c',
);

Future<void> _pumpPrompt(
  WidgetTester tester,
  AppDatabase db, {
  required bool guest,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentAccountIdProvider.overrideWithValue(testAccountId),
        accountProvider.overrideWith(
          (ref) => Stream.value(_account(guest: guest)),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: LinkAccountPrompt())),
    ),
  );
  for (var beat = 0; beat < 10; beat++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Tears the tree down while the binding is still pumping.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

Future<void> _joinAGroup(AppDatabase db) =>
    DriftGroupRepository(db).createGroup(
      name: 'Goa',
      defaultCurrency: 'INR',
      creatorDisplayName: 'Me',
      creatorProfileId: testAccountId,
    );

void main() {
  late AppDatabase db;

  setUp(() async => db = await testDatabase());
  tearDown(() => db.close());

  group('the prompt to save a guest account', () {
    testWidgets('shows as soon as the guest is in any group', (tester) async {
      await _joinAGroup(db);
      await _pumpPrompt(tester, db, guest: true);

      expect(find.text('Protect access to this guest account'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('waits while there is nothing on the server to lose', (
      tester,
    ) async {
      await _pumpPrompt(tester, db, guest: true);

      expect(find.text('Protect access to this guest account'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('never shows to an account that can sign back in', (
      tester,
    ) async {
      await _joinAGroup(db);
      await _pumpPrompt(tester, db, guest: false);

      expect(find.text('Protect access to this guest account'), findsNothing);
      await _teardown(tester);
    });
  });
}
