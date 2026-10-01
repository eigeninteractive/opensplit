import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/backend_providers.dart';
import 'package:opensplit/application/preferences_providers.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpFreshInstall(WidgetTester tester) async {
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
}

void main() {
  testWidgets('a fresh install reaches welcome without opening a ledger', (
    tester,
  ) async {
    await _pumpFreshInstall(tester);

    expect(find.text('OpenSplit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // flutter_localizations' delegates, which `flutter gen-l10n` lists, supply
  // the framework's MaterialLocalizations type rather than material_ui's, and
  // material_ui would quietly fall back to its hard-coded defaults.
  testWidgets('Material widgets get material_ui localizations', (tester) async {
    await _pumpFreshInstall(tester);

    final context = tester.element(find.text('OpenSplit'));
    expect(
      MaterialLocalizations.of(context),
      isA<GlobalMaterialLocalizations>(),
    );
  });
}
