import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a fresh install reaches welcome without opening a ledger', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final sessions = await SessionStore.load(
      preferences,
      vault: MemoryTokenVault(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sessionStoreProvider.overrideWithValue(sessions),
        ],
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenSplit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
