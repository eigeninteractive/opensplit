import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/presentation/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a fresh install reaches welcome without opening a ledger', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const OpenSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenSplit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
