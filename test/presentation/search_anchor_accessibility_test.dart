import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit/application/ledger_providers.dart';
import 'package:opensplit/presentation/widgets/currency_picker.dart';
import 'package:opensplit/presentation/widgets/group_search_button.dart';

void main() {
  testWidgets('the buttons that open search have labeled tap targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currenciesProvider.overrideWith((_) => Stream.value({}))],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  const GroupSearchButton(groupId: 'example'),
                  CurrencyButton(code: 'EUR', onChanged: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });
}
